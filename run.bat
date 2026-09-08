@echo off
REM ---------------------------------------------------------------------------
REM Convenience launcher at the top of the repository.
REM
REM The real script is Sources\run.bat; this only forwards to it so there is one
REM copy of the logic. Arguments and the exit code are passed straight through.
REM
REM Usage:  run.bat [arguments passed to BUSMASTER]
REM ---------------------------------------------------------------------------

call "%~dp0Sources\run.bat" %*
exit /b %ERRORLEVEL%
