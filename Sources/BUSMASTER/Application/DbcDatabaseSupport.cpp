/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * \file      DbcDatabaseSupport.cpp
 * \brief     Implementation of the *.dbc association helpers
 */

#include "stdafx.h"
#include "DbcDatabaseSupport.h"
#include "HashDefines.h"
#include "Utility/Utility.h"
#include "Utility/MultiLanguageSupport.h"
#include "../../Kernel/ProtocolDefinitions/ProtocolsDefinitions.h"

#include <shlwapi.h>
#include <cctype>

/* Mirror of the plugin interface published by
   Format Converter/DBC2DBFConverterLibrary/DBCConverterBase.h.
   That header cannot be included here: it drags in CMessage and CSignal, which
   are declared __declspec(dllexport), so every translation unit that sees them
   re-exports members it has no definition for. The converter is reached through
   LoadLibrary rather than its import library precisely so that a missing
   DBC2DBFConverterLibrary.dll degrades to "cannot convert" instead of stopping
   BUSMASTER from starting, which rules out linking the exports in.

   Only the vtable layout matters here, so the declarations below must stay in
   the same order as the original, trailing virtual destructor included. Keep
   the two in step when the converter interface changes. */
class CMessage;

class CDBCConverterBase
{
public:
    virtual HRESULT LoadDBCFile(CString strDBCFile) = 0;
    virtual HRESULT GenerateImportList() = 0;
    virtual HRESULT ConvertFile(CString strDBFFile) = 0;
    virtual HRESULT FindMessage(CString strMsgName, CMessage*) = 0;
    virtual HRESULT FindMessage(UINT unMsgId, CMessage*) = 0;
    virtual HRESULT GetResultString(char* pchResult) = 0;
    virtual HRESULT FindSignalAlias(CString& strMsgName, CString& strSignalName, CString& strSignalAlias) = 0;
    virtual HRESULT ClearMsgList() = 0;
    virtual HRESULT GetMessageNameList(CStringArray& messageList) = 0;
    virtual ~CDBCConverterBase() {};
};

typedef HRESULT (*GETCONVERTER)(CDBCConverterBase*& ouDBCConverter, ETYPE_BUS);

/** Sub folder of the BUSMASTER user data folder holding the shadow databases */
#define defDBC_SHADOW_FOLDER    "DbcShadowDb"

/** The converter lives beside the other format converter plugins */
#define defDBC_CONVERTER_DLL    "DBC2DBFConverterLibrary.dll"
#define defCONVERTER_PLUGIN_DIR "ConverterPlugins"

namespace
{
    /**
     * A stable, case insensitive hash of the source path. Two *.dbc files
     * sharing a name in different folders must not share a shadow database.
     */
    std::string strHashOfPath(const std::string& strPath)
    {
        /* FNV-1a, 32 bit */
        unsigned int unHash = 2166136261u;
        for (std::string::const_iterator itr = strPath.begin(); itr != strPath.end(); ++itr)
        {
            unHash ^= (unsigned char)tolower((unsigned char)*itr);
            unHash *= 16777619u;
        }

        char acHash[16];
        sprintf_s(acHash, sizeof(acHash), "%08x", unHash);
        return std::string(acHash);
    }

    /**
     * Last write time of a file, or 0 when it cannot be read.
     */
    unsigned __int64 nGetLastWriteTime(const std::string& strPath)
    {
        WIN32_FILE_ATTRIBUTE_DATA sAttributes;
        if (0 == GetFileAttributesEx(strPath.c_str(), GetFileExInfoStandard, &sAttributes))
        {
            return 0;
        }

        ULARGE_INTEGER uTime;
        uTime.LowPart  = sAttributes.ftLastWriteTime.dwLowDateTime;
        uTime.HighPart = sAttributes.ftLastWriteTime.dwHighDateTime;
        return uTime.QuadPart;
    }

    /**
     * Full path of the folder the shadow databases are kept in. The folder is
     * created when it is missing.
     */
    bool bGetShadowFolder(std::string& strFolder)
    {
        std::string strUserData;
        if (S_OK != GetCurrentVerBusMasterUserDataPath(strUserData))
        {
            return false;
        }

        char acFolder[MAX_PATH];
        PathCombine(acFolder, strUserData.c_str(), defDBC_SHADOW_FOLDER);

        if ((0 == CreateDirectory(acFolder, nullptr)) &&
                (ERROR_ALREADY_EXISTS != GetLastError()))
        {
            return false;
        }

        strFolder = acFolder;
        return true;
    }

    /**
     * Loads the bundled DBC to DBF converter. It is deployed next to the other
     * format converter plugins, so the plugin folder is tried before letting
     * the loader search its usual paths.
     *
     * The module is deliberately left resident: it is an MFC extension DLL,
     * and attaching and detaching it from the resource chain around every
     * conversion buys nothing.
     */
    HMODULE hLoadConverterLibrary()
    {
        std::string strInstallFolder;
        if (S_OK == GetBusmasterInstalledFolder(strInstallFolder))
        {
            char acPluginDir[MAX_PATH];
            char acDllPath[MAX_PATH];
            PathCombine(acPluginDir, strInstallFolder.c_str(), defCONVERTER_PLUGIN_DIR);
            PathCombine(acDllPath, acPluginDir, defDBC_CONVERTER_DLL);

            HMODULE hModule = LoadLibrary(acDllPath);
            if (nullptr != hModule)
            {
                return hModule;
            }
        }

        return LoadLibrary(defDBC_CONVERTER_DLL);
    }
}

bool bIsDbcDatabaseFile(const std::string& strFilePath)
{
    std::string::size_type nDot = strFilePath.find_last_of('.');
    if (std::string::npos == nDot)
    {
        return false;
    }

    std::string strExtension = strFilePath.substr(nDot + 1);
    for (std::string::iterator itr = strExtension.begin(); itr != strExtension.end(); ++itr)
    {
        *itr = (char)toupper((unsigned char)*itr);
    }

    return (strExtension == CANOE_DATABASE_EXTN);
}

bool bConvertDbcToShadowDbf(const std::string& strDbcPath,
                            std::string& strDbfPath,
                            std::string& strError)
{
    strError.clear();

    const unsigned __int64 nDbcTime = nGetLastWriteTime(strDbcPath);
    if (0 == nDbcTime)
    {
        strError = _("The database file could not be opened.");
        return false;
    }

    std::string strFolder;
    if (false == bGetShadowFolder(strFolder))
    {
        strError = _("The BUSMASTER user data folder could not be created.");
        return false;
    }

    /* <stem>_<hash of full path>.dbf keeps the generated name recognisable
    while staying unique across folders. */
    char acStem[MAX_PATH];
    strcpy_s(acStem, sizeof(acStem), PathFindFileName(strDbcPath.c_str()));
    PathRemoveExtension(acStem);

    std::string strShadowName = std::string(acStem) + "_" + strHashOfPath(strDbcPath) + ".dbf";

    char acShadowPath[MAX_PATH];
    PathCombine(acShadowPath, strFolder.c_str(), strShadowName.c_str());

    /* Reuse the previous conversion while it is not older than its source. */
    const unsigned __int64 nShadowTime = nGetLastWriteTime(acShadowPath);
    if ((0 != nShadowTime) && (nShadowTime >= nDbcTime))
    {
        strDbfPath = acShadowPath;
        return true;
    }

    HMODULE hConverterLib = hLoadConverterLibrary();
    if (nullptr == hConverterLib)
    {
        strError = _("DBC2DBFConverterLibrary.dll could not be loaded.");
        return false;
    }

    bool bResult = false;
    GETCONVERTER pfGetConverter = (GETCONVERTER)GetProcAddress(hConverterLib, "GetDBCConverter");
    if (nullptr == pfGetConverter)
    {
        strError = _("DBC2DBFConverterLibrary.dll does not export GetDBCConverter.");
    }
    else
    {
        CDBCConverterBase* pouConverter = nullptr;
        if ((S_OK == pfGetConverter(pouConverter, CAN)) && (nullptr != pouConverter))
        {
            pouConverter->ClearMsgList();

            /* Drop any earlier attempt first, so a conversion that fails part
            way through cannot leave a stale shadow that later looks current. */
            DeleteFile(acShadowPath);

            HRESULT hLoadResult = pouConverter->LoadDBCFile(strDbcPath.c_str());
            HRESULT hConvertResult = S_FALSE;
            if (S_OK == hLoadResult)
            {
                hConvertResult = pouConverter->ConvertFile(acShadowPath);
            }

            /* A *.dbc the converter could only partly read still yields a
            usable database, so whether the output exists decides the outcome
            and the converter's own wording is passed back as a warning. */
            bResult = (0 != nGetLastWriteTime(acShadowPath));

            if ((S_OK != hLoadResult) || (S_OK != hConvertResult))
            {
                char acResult[1024] = "";
                pouConverter->GetResultString(acResult);
                strError = acResult;
            }

            delete pouConverter;
        }
        else
        {
            strError = _("The DBC converter could not be created.");
        }
    }

    if (bResult)
    {
        strDbfPath = acShadowPath;
    }

    return bResult;
}
