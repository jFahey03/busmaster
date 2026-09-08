@echo off
setlocal enabledelayedexpansion

REM ---------------------------------------------------------------------------
REM Builds BUSMASTER with a modern Visual Studio.
REM
REM The projects were written for the Visual Studio 2013 toolset (v120 /
REM v120_xp), which is no longer obtainable. Rather than rewriting all 81
REM project files, the toolset is overridden here: properties passed with /p:
REM are global and take precedence over the values inside each .vcxproj, so the
REM retarget is entirely contained in this script and is undone by removing the
REM two switches in RETARGET below.
REM
REM Whichever toolset the installed Visual Studio actually ships is detected and
REM used, so this does not need editing when Visual Studio moves on. To pin one
REM explicitly, set it first:   set PLATFORM_TOOLSET=v143
REM
REM Usage:  build.bat [nopause]
REM         Pauses at the end so the window stays readable when double clicked.
REM         Pass "nopause" for unattended builds.
REM
REM A full MSBuild log is written to build.log next to this script.
REM ---------------------------------------------------------------------------

pushd "%~dp0"

set BUILD_STEP=
set LOGFILE=%~dp0build.log
if exist "%LOGFILE%" del "%LOGFILE%"

:VSWHERE_FIND
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
if exist "%VSWHERE%" goto VSWHERE_FOUND
set VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe
if exist "%VSWHERE%" goto VSWHERE_FOUND

echo.
echo ERROR: vswhere.exe not found, so no Visual Studio 2017 or later is installed.
goto NEED_VS

:VSWHERE_FOUND
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -property installationPath 2^>nul`) do set VSINSTALL=%%i

if not defined VSINSTALL (
    echo.
    echo ERROR: No Visual Studio installation was found.
    goto NEED_VS
)

:MSBUILD_FIND
set MSBUILD=%VSINSTALL%\MSBuild\Current\Bin\MSBuild.exe
if exist "%MSBUILD%" goto TOOLSET_FIND

echo.
echo ERROR: MSBuild not found under %VSINSTALL%
echo        The C++ workload is probably not installed.
goto NEED_VS

:TOOLSET_FIND
REM Find a platform toolset that is genuinely usable. Three things have to line
REM up and they are held in three different places:
REM
REM   1. MSBuild\Microsoft\VC\<vNNN> is the VISUAL STUDIO version (v170 = 2022,
REM      v180 = 2026), not a toolset. The toolsets live one level down under
REM      Platforms\Win32\PlatformToolsets.
REM   2. A toolset directory can exist with no compiler behind it. The file
REM      VC\Auxiliary\Build\Microsoft.VCToolsVersion.<toolset>.default.txt names
REM      the MSVC version that backs it.
REM   3. MFC is installed per MSVC version, so it has to be checked against the
REM      version backing the chosen toolset, not against any version present.
REM
REM The oldest complete toolset wins: this code was written for Visual Studio
REM 2013, so the least modern compiler available is the least painful.

set FOUND_ANY_TARGETS=
set CHOSEN_TOOLSET=

REM Each Visual Studio version folder registers the toolsets it brought with
REM it, so an older toolset installed alongside a newer Visual Studio lives
REM under the older folder: on a 2026 install with the 2022 tools added, v143
REM sits under v170 while v145 sits under v180. Scan them all.
REM
REM Ascending order means older toolsets are considered first, and the first
REM complete one wins. That is deliberate: this code was written for Visual
REM Studio 2013, so the least modern compiler available is the least painful.

echo Toolsets present in %VSINSTALL%:
for /f "delims=" %%v in ('dir /b /ad /on "%VSINSTALL%\MSBuild\Microsoft\VC\v*" 2^>nul') do (
    if exist "%VSINSTALL%\MSBuild\Microsoft\VC\%%v\Platforms\Win32\PlatformToolsets" (
        set FOUND_ANY_TARGETS=1
        for /f "delims=" %%t in ('dir /b /ad /on "%VSINSTALL%\MSBuild\Microsoft\VC\%%v\Platforms\Win32\PlatformToolsets" 2^>nul') do (
            REM Read the version with FOR rather than "set /p": set /p reads
            REM standard input, which corrupts the pipe the enclosing FOR is
            REM already consuming and makes iterations come out garbled.
            set MSVCVER=
            for /f "usebackq delims=" %%m in ("%VSINSTALL%\VC\Auxiliary\Build\Microsoft.VCToolsVersion.%%t.default.txt") do set MSVCVER=%%m
            if "!MSVCVER!"=="" (
                echo     %%t   no MSVC version recorded, compiler=NO   MFC=NO
            ) else (
                set HAS_CL=NO
                set HAS_MFC=NO
                if exist "%VSINSTALL%\VC\Tools\MSVC\!MSVCVER!\bin\Hostx86\x86\cl.exe" set HAS_CL=yes
                if exist "%VSINSTALL%\VC\Tools\MSVC\!MSVCVER!\bin\Hostx64\x86\cl.exe" set HAS_CL=yes
                if exist "%VSINSTALL%\VC\Tools\MSVC\!MSVCVER!\atlmfc\include\afxwin.h" set HAS_MFC=yes
                echo     %%t   MSVC !MSVCVER!   compiler=!HAS_CL!   MFC=!HAS_MFC!
                if "!HAS_CL!"=="yes" if "!HAS_MFC!"=="yes" if "!CHOSEN_TOOLSET!"=="" set CHOSEN_TOOLSET=%%t
            )
        )
    )
)
echo.

if not defined FOUND_ANY_TARGETS (
    echo ERROR: No C++ build targets found under
    echo        %VSINSTALL%\MSBuild\Microsoft\VC
    echo        The "Desktop development with C++" workload is not installed.
    goto NEED_VS
)

REM An explicit pin overrides the search.
if not "%PLATFORM_TOOLSET%"=="" set CHOSEN_TOOLSET=%PLATFORM_TOOLSET%

if not "%CHOSEN_TOOLSET%"=="" goto BUILD_START

echo ERROR: No usable C++ toolset found.
echo.
echo A toolset needs BOTH a compiler and MFC, and they are installed
echo separately. Open the Visual Studio Installer, choose Modify, then the
echo Individual components tab, and add whichever half is missing above:
echo.
echo     compiler=NO   add  "MSVC v___ - VS 20__ C++ x64/x86 build tools"
echo     MFC=NO        add  "C++ MFC for v___ build tools"
echo.
echo The MFC component must match the toolset version exactly. MFC installed
echo for one toolset does nothing for another.
echo.
goto FAILED

:NEED_VS
echo.
echo Install Visual Studio Community ^(free^) from
echo     https://visualstudio.microsoft.com/downloads/
echo.
echo Take the Community edition under the "Visual Studio" heading. Do NOT take
echo "Visual C++ Redistributable" from the "Other Tools, Frameworks, and
echo Redistributables" section: that is only the run time library and contains
echo no compiler.
echo.
echo In the installer select:
echo     - Workload: Desktop development with C++
echo     - Individual components: C++ MFC for latest build tools ^(x86 ^& x64^)
echo.
goto FAILED

:BUILD_START
REM Retarget switches and the file logger, applied to every MSBuild call below.
set RETARGET=/p:PlatformToolset=%CHOSEN_TOOLSET% /p:WindowsTargetPlatformVersion=10.0
set LOGGER=/fileLogger /fileLoggerParameters:LogFile="%LOGFILE%";Append;Verbosity=normal
set COMMON=/property:Configuration=Release %RETARGET% %LOGGER%

echo Visual Studio : %VSINSTALL%
echo MSBuild       : %MSBUILD%
echo Toolset       : %CHOSEN_TOOLSET%  (projects request v120 / v120_xp; overridden here)
echo Log           : %LOGFILE%
echo.

:BUILD
set BUILD_STEP=Kernel
echo [1/7] Kernel
"%MSBUILD%" "Kernel\BusmasterKernel.sln" %COMMON%
if errorlevel 1 goto FAILED

set BUILD_STEP=BUSMASTER
echo [2/7] BUSMASTER
"%MSBUILD%" "BUSMASTER\BUSMASTER.sln" %COMMON%
if errorlevel 1 goto FAILED

REM CAN PEAK USB. The project is not in the tree any more and is not part of
REM BUSMASTER.sln; BIN\Release\CAN_PEAK_USB.dll is committed prebuilt. Guarded
REM rather than deleted so it builds again if the project is restored.
set BUILD_STEP=CAN_PEAK_USB
if exist "BUSMASTER\CAN_PEAK_USB\CAN_PEAK_USB.vcxproj" (
    echo [3/7] CAN_PEAK_USB
    "%MSBUILD%" "BUSMASTER\CAN_PEAK_USB\CAN_PEAK_USB.vcxproj" %COMMON%
    if errorlevel 1 goto FAILED
) else (
    echo [3/7] CAN_PEAK_USB - skipped, no project in tree ^(prebuilt DLL is used^)
)

set BUILD_STEP=Language Dlls
echo [4/7] Language Dlls
"%MSBUILD%" "BUSMASTER\Language Dlls\Language Dlls.sln" %COMMON%
if errorlevel 1 goto FAILED

set QTPATH=%QTDIR%
if "%QTPATH%"=="" set QTPATH=C:\Qt\Qt5.5.1\5.5\msvc2013

set BUILD_STEP=LDFEditor
if exist "%QTPATH%\bin\moc.exe" (
    echo [5/7] LDFEditor
    "%MSBUILD%" "BUSMASTER\LDFEditor\LDFEditor.sln" %COMMON%
    if errorlevel 1 goto FAILED
) else (
    echo [5/7] LDFEditor - skipped, Qt not found at %QTPATH%
)

set BUILD_STEP=LDFViewer
if exist "%QTPATH%\bin\moc.exe" (
    echo [6/7] LDFViewer
    "%MSBUILD%" "BUSMASTER\LDFViewer\LDFViewer.sln" %COMMON%
    if errorlevel 1 goto FAILED
) else (
    echo [6/7] LDFViewer - skipped, Qt not found at %QTPATH%
)

:GENERATE_PARSERS
REM Absolute paths throughout, so a failure part way cannot leave the working
REM directory somewhere unexpected.
set FLEX=%~dp0..\Tools\flex\flex.exe
set BISON=%~dp0..\Tools\bison\bison.exe
REM bison looks for its parser skeleton in the current directory unless
REM BISON_SIMPLE says otherwise. The original script cd'd into Tools\bison to
REM satisfy that; setting the variable keeps the absolute paths above working.
set BISON_SIMPLE=%~dp0..\Tools\bison\bison.simple

if not exist "%FLEX%" (
    set BUILD_STEP=flex
    echo.
    echo ERROR: flex.exe not found at %FLEX%
    goto FAILED
)
if not exist "%BISON%" (
    set BUILD_STEP=bison
    echo.
    echo ERROR: bison.exe not found at %BISON%
    goto FAILED
)

REM Asc Log
set BUILD_STEP=AscLogConverter lexer
"%FLEX%" -i -L -o"BUSMASTER\Format Converter\AscLogConverter\Asc_Log_Lexer.c" "BUSMASTER\Format Converter\AscLogConverter\Asc_Log_Lexer.l"
if errorlevel 1 goto FAILED

set BUILD_STEP=AscLogConverter parser
"%BISON%" -d -l -o"BUSMASTER\Format Converter\AscLogConverter\Asc_Log_Parser.c" "BUSMASTER\Format Converter\AscLogConverter\Asc_Log_Parser.y"
if errorlevel 1 goto FAILED

REM Log Asc
set BUILD_STEP=LogAscConverter lexer
"%FLEX%" -i -L -o"BUSMASTER\Format Converter\LogAscConverter\Log_Asc_Lexer.c" "BUSMASTER\Format Converter\LogAscConverter\Log_Asc_Lexer.l"
if errorlevel 1 goto FAILED

set BUILD_STEP=LogAscConverter parser
"%BISON%" -d -l -o"BUSMASTER\Format Converter\LogAscConverter\Log_Asc_Parser.c" "BUSMASTER\Format Converter\LogAscConverter\Log_Asc_Parser.y"
if errorlevel 1 goto FAILED

REM The format converters produce DBC2DBFConverterLibrary.dll, which the
REM application loads at run time to read a *.dbc the database manager will not
REM parse itself. Its post build step drops it into BIN\<config>\ConverterPlugins.
set BUILD_STEP=Format Converter
echo [7/7] Format Converter
"%MSBUILD%" "BUSMASTER\Format Converter\FormatConverter.sln" %COMMON%
if errorlevel 1 goto FAILED

:SUCCESS
echo.
echo ===============================================================
echo  BUILD SUCCEEDED
echo  Output: %~dp0BUSMASTER\BIN\Release
echo  Log:    %LOGFILE%
echo ===============================================================
popd
if /i not "%~1"=="nopause" pause
endlocal
exit /b 0

:FAILED
echo.
echo ===============================================================
if defined BUILD_STEP (
    echo  BUILD FAILED at step: %BUILD_STEP%
) else (
    echo  BUILD FAILED
)
if exist "%LOGFILE%" echo  Full log: %LOGFILE%
echo ===============================================================

REM BusEmulation registers itself as a COM server after linking, which writes
REM to HKEY_CLASSES_ROOT and so needs elevation. The application depends on
REM BusEmulation, so this one step stops everything downstream.
if exist "%LOGFILE%" findstr /c:"/RegServer" "%LOGFILE%" >nul 2>&1 && (
    echo.
    echo  BusEmulation could not register itself as a COM server. That step
    echo  writes to HKEY_CLASSES_ROOT and needs Administrator rights, and the
    echo  application depends on BusEmulation, so nothing after it is built.
    echo.
    echo  Right click build.bat and choose "Run as administrator".
    echo.
    echo  This is needed on every run, not just the first: BusEmulation
    echo  relinks each build because MIDL regenerates its type library, so
    echo  the registration step never gets skipped.
    echo.
)

popd
if /i not "%~1"=="nopause" pause
endlocal
exit /b 1
