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

where cscript.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] cscript.exe is unavailable. Solution Hub and Knowledge Base parsing require Windows Script Host.
  exit /b 1
)
echo [PASS] cscript.exe

where tar.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] tar.exe is unavailable. Native self-update requires the Windows inbox tar.exe.
  exit /b 1
)
echo [PASS] tar.exe

where robocopy.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] robocopy.exe is unavailable. Native self-update requires robocopy.exe.
  exit /b 1
)
echo [PASS] robocopy.exe

echo [INFO] Verifying application file integrity...

for %%F in (run.bat docs-downloader.bat solution-downloader.bat kb-downloader.bat update.bat scripts\fortinet-parser.js VERSION) do (
  if not exist "%%F" (
    echo [FAIL] Required application file is missing: %%F
    exit /b 1
  )
)

findstr /x /c:":hubs" "solution-downloader.bat" >nul
if errorlevel 1 (
  echo [FAIL] solution-downloader.bat is incomplete: missing :hubs label.
  echo        Run: run.bat update
  exit /b 1
)
findstr /x /c:":lookup_duplicate_remote" "solution-downloader.bat" >nul
if errorlevel 1 (
  echo [FAIL] solution-downloader.bat is incomplete: missing :lookup_duplicate_remote label.
  echo        Run: run.bat update
  exit /b 1
)
findstr /x /c:":write_source" "solution-downloader.bat" >nul
if errorlevel 1 (
  echo [FAIL] solution-downloader.bat is incomplete: missing :write_source label.
  echo        Run: run.bat update
  exit /b 1
)
findstr /x /c:":categories" "kb-downloader.bat" >nul
if errorlevel 1 (
  echo [FAIL] kb-downloader.bat is incomplete: missing :categories label.
  echo        Run: run.bat update
  exit /b 1
)
findstr /x /c:":process_article" "kb-downloader.bat" >nul
if errorlevel 1 (
  echo [FAIL] kb-downloader.bat is incomplete: missing :process_article label.
  echo        Run: run.bat update
  exit /b 1
)
findstr /x /c:":apply" "update.bat" >nul
if errorlevel 1 (
  echo [FAIL] update.bat is incomplete: missing :apply label.
  exit /b 1
)
findstr /x /c:":rollback" "update.bat" >nul
if errorlevel 1 (
  echo [FAIL] update.bat is incomplete: missing :rollback label.
  exit /b 1
)
echo [PASS] application files and critical batch labels

if not exist "runtime" mkdir "runtime"
if not exist "runtime\downloads" mkdir "runtime\downloads"
if not exist "runtime\temp" mkdir "runtime\temp"
if not exist "runtime\state" mkdir "runtime\state"
if not exist "runtime\state\downloads.db" type nul > "runtime\state\downloads.db"
if not exist "runtime\state\catalogue.db" type nul > "runtime\state\catalogue.db"
if not exist "runtime\state\sources.db" type nul > "runtime\state\sources.db"
if not exist "runtime\state\kb.db" type nul > "runtime\state\kb.db"
if not exist "runtime\state\kb-history.db" type nul > "runtime\state\kb-history.db"
if not exist "runtime\kb" mkdir "runtime\kb"
if not exist "runtime\kb\articles" mkdir "runtime\kb\articles"

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
if not exist "runtime\state\sources.db" (
  echo [FAIL] Could not create runtime\state\sources.db.
  exit /b 1
)
if not exist "runtime\state\kb.db" (
  echo [FAIL] Could not create runtime\state\kb.db.
  exit /b 1
)
if not exist "runtime\kb\articles" (
  echo [FAIL] Could not create runtime\kb\articles.
  exit /b 1
)

echo [PASS] runtime directories, tracking databases, and corpus state
echo.
echo Installation check complete.
echo Launch with: run.bat
exit /b 0
