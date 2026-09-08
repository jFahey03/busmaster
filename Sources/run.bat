@echo off
setlocal

REM ---------------------------------------------------------------------------
REM Launches the BUSMASTER produced by build.bat.
REM
REM Usage:  run.bat [arguments passed to BUSMASTER]
REM
REM         run.bat
REM         run.bat "C:\path\to\some.cfx"     opens a configuration directly
REM
REM Set BM_CONFIG to pick a different build, for example:
REM         set BM_CONFIG=Debug
REM ---------------------------------------------------------------------------

pushd "%~dp0"

if "%BM_CONFIG%"=="" set BM_CONFIG=Release
set BMDIR=%~dp0BUSMASTER\BIN\%BM_CONFIG%
set BMEXE=%BMDIR%\BUSMASTER.exe

if not exist "%BMEXE%" (
    echo.
    echo ERROR: %BMEXE%
    echo        was not found. Build it first:
    echo.
    echo            build.bat
    echo.
    popd
    endlocal
    pause
    exit /b 1
)

REM The simulated bus needs BusEmulation registered as a COM server. Without it
REM CAN_STUB cannot create BusEmulation.SimENG, and the simulated bus reports an
REM error. Registering writes to HKEY_CLASSES_ROOT, so it needs elevation and
REM cannot be done from here. Everything else works without it.
set BMSIM=
reg query "HKCR\BusEmulation.SimENG" >nul 2>&1
if not errorlevel 1 set BMSIM=1
reg query "HKCR\BusEmulation.SimENG" /reg:32 >nul 2>&1
if not errorlevel 1 set BMSIM=1

if not defined BMSIM (
    echo NOTE: the simulated bus is unavailable ^(BusEmulation.SimENG is not registered^).
    echo       To enable it, run this once from an elevated prompt:
    echo.
    echo           "%BMDIR%\BusEmulation.exe" /RegServer
    echo.
)

echo Starting %BMEXE%
start "BUSMASTER" /D "%BMDIR%" "%BMEXE%" %*

popd
endlocal
exit /b 0
