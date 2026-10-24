@echo off
setlocal
cd /d "%~dp0"
set "R_LIBS_USER=%~dp0runtime\library"
set "RDATACRAFT_RUNTIME=%~dp0runtime"
set "RHOME=%~dp0runtime\R"
set "R_HOME=%~dp0runtime\R"
set "RDATACRAFT_RSCRIPT=%~dp0runtime\R\bin\x64\Rscript.exe"
if not exist "%RDATACRAFT_RSCRIPT%" set "RDATACRAFT_RSCRIPT=%~dp0runtime\R\bin\Rscript.exe"
if not exist "%RDATACRAFT_RSCRIPT%" (
  echo Restore the full Windows portable bundle before validation.
  pause
  exit /b 1
)
"%RDATACRAFT_RSCRIPT%" --vanilla scripts/validate.R
set "RDATACRAFT_CHECK_EXIT=%ERRORLEVEL%"
if /I not "%~1"=="--no-pause" pause
exit /b %RDATACRAFT_CHECK_EXIT%
