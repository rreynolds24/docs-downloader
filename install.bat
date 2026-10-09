@echo off
setlocal
cd /d "%~dp0"

echo Fortinet Docs Downloader - installer/doctor
echo.

where cmd.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] cmd.exe is unavailable.
  exit /b 1
)
echo [PASS] cmd.exe

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe is unavailable. This tool requires the Windows inbox curl.exe.
  exit /b 1
)
echo [PASS] curl.exe

where findstr.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] findstr.exe is unavailable.
  exit /b 1
)
echo [PASS] findstr.exe

where certutil.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] certutil.exe is unavailable. SHA-256 content identity requires the Windows inbox certutil.exe.
  exit /b 1
)
echo [PASS] certutil.exe

if not exist "runtime" mkdir "runtime"
if not exist "runtime\downloads" mkdir "runtime\downloads"
if not exist "runtime\temp" mkdir "runtime\temp"
if not exist "runtime\state" mkdir "runtime\state"
if not exist "runtime\state\downloads.db" type nul > "runtime\state\downloads.db"
if not exist "runtime\state\catalogue.db" type nul > "runtime\state\catalogue.db"

if not exist "runtime\downloads" (
  echo [FAIL] Could not create runtime\downloads.
  exit /b 1
)
if not exist "runtime\temp" (
  echo [FAIL] Could not create runtime\temp.
  exit /b 1
)
if not exist "runtime\state" (
  echo [FAIL] Could not create runtime\state.
  exit /b 1
)
if not exist "runtime\state\downloads.db" (
  echo [FAIL] Could not create runtime\state\downloads.db.
  exit /b 1
)
if not exist "runtime\state\catalogue.db" (
  echo [FAIL] Could not create runtime\state\catalogue.db.
  exit /b 1
)

echo [PASS] runtime directories, tracking database, and version catalogue
echo.
echo Installation check complete.
echo Launch with: run.bat
exit /b 0
