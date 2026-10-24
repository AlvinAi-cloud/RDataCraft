@echo off
setlocal
cd /d "%~dp0"
set "R_LIBS_USER=%~dp0runtime\library"
set "RDATACRAFT_RUNTIME=%~dp0runtime"
set "RDATACRAFT_PORTABLE=1"
set "R_USER_CACHE_DIR=%TEMP%\RDataCraft\cache"
set "RDATACRAFT_RSCRIPT=%~dp0runtime\R\bin\x64\Rscript.exe"
if not exist "%RDATACRAFT_RSCRIPT%" set "RDATACRAFT_RSCRIPT=%~dp0runtime\R\bin\Rscript.exe"
if exist "%RDATACRAFT_RSCRIPT%" (
  set "RHOME=%~dp0runtime\R"
  set "R_HOME=%~dp0runtime\R"
  "%RDATACRAFT_RSCRIPT%" --vanilla scripts/portable.R %*
) else (
  powershell.exe -NoProfile -File "%~dp0Launch RDataCraft.ps1" %*
)
set "RDATACRAFT_LAUNCH_EXIT=%ERRORLEVEL%"
if not "%RDATACRAFT_LAUNCH_EXIT%"=="0" pause
exit /b %RDATACRAFT_LAUNCH_EXIT%
