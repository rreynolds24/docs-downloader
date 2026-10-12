@echo off
setlocal EnableExtensions EnableDelayedExpansion

if /i "%~1"=="--apply" goto :apply

cd /d "%~dp0"
if not exist "runtime\temp" mkdir "runtime\temp" >nul 2>&1
if not exist "runtime\temp" (
  echo [FAIL] Could not create runtime\temp for the updater.
  exit /b 1
)

copy /y "%~f0" "runtime\temp\docs-downloader-update-helper.bat" >nul
if errorlevel 1 (
  echo [FAIL] Could not stage the update helper.
  exit /b 1
)

call "runtime\temp\docs-downloader-update-helper.bat" --apply "%~dp0"
exit /b %errorlevel%

:apply
set "ROOT=%~2"
if not defined ROOT exit /b 2
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
cd /d "%ROOT%"

set "UPDATE_URL=https://github.com/rreynolds24/docs-downloader/archive/refs/heads/main.zip"
if defined DOCS_DOWNLOADER_UPDATE_URL set "UPDATE_URL=%DOCS_DOWNLOADER_UPDATE_URL%"

set "WORK=%ROOT%\runtime\temp\update"
set "ZIP=%WORK%\latest.zip"
set "EXTRACT=%WORK%\extract"
set "BACKUP=%WORK%\backup"

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe is required for update.
  exit /b 1
)
where tar.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] tar.exe is required for update.
  exit /b 1
)
where robocopy.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] robocopy.exe is required for update.
  exit /b 1
)

if exist "%WORK%" rmdir /s /q "%WORK%" >nul 2>&1
mkdir "%EXTRACT%" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Could not create update workspace.
  exit /b 1
)

echo [INFO] Downloading latest docs-downloader release source...
curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 180 "%UPDATE_URL%" -o "%ZIP%"
if errorlevel 1 (
  echo [FAIL] Could not download update package.
  exit /b 3
)

echo [INFO] Extracting update package...
tar.exe -xf "%ZIP%" -C "%EXTRACT%"
if errorlevel 1 (
  echo [FAIL] Could not extract update package.
  exit /b 4
)

set "SOURCE="
for /d %%D in ("%EXTRACT%\*") do (
  if not defined SOURCE if exist "%%~fD\VERSION" if exist "%%~fD\run.bat" set "SOURCE=%%~fD"
)
if not defined SOURCE (
  echo [FAIL] Update package did not contain a valid docs-downloader root.
  exit /b 5
)

set "CURRENT_VERSION=unknown"
set "NEW_VERSION=unknown"
if exist "%ROOT%\VERSION" set /p CURRENT_VERSION=<"%ROOT%\VERSION"
set /p NEW_VERSION=<"!SOURCE!\VERSION"

if /i "!CURRENT_VERSION!"=="!NEW_VERSION!" (
  echo [PASS] Already current: v!CURRENT_VERSION!
  rmdir /s /q "%WORK%" >nul 2>&1
  exit /b 0
)

echo [INFO] Creating rollback snapshot...
mkdir "%BACKUP%" >nul 2>&1
robocopy.exe "%ROOT%" "%BACKUP%" /E /R:2 /W:1 /XD runtime .git /NFL /NDL /NJH /NJS /NP >nul
set "BACKUP_RC=!ERRORLEVEL!"
if !BACKUP_RC! GEQ 8 (
  echo [FAIL] Could not create rollback snapshot. robocopy exit code !BACKUP_RC!.
  exit /b 6
)

echo [INFO] Updating v!CURRENT_VERSION! to v!NEW_VERSION!...
robocopy.exe "!SOURCE!" "%ROOT%" /E /R:2 /W:1 /XD runtime .git /NFL /NDL /NJH /NJS /NP >nul
set "ROBOCOPY_RC=!ERRORLEVEL!"
if !ROBOCOPY_RC! GEQ 8 (
  echo [FAIL] File overlay failed. robocopy exit code !ROBOCOPY_RC!.
  call :rollback
  exit /b 6
)

if not exist "%ROOT%\run.bat" (
  echo [FAIL] Updated run.bat is missing.
  exit /b 7
)
if not exist "%ROOT%\docs-downloader.bat" (
  echo [FAIL] Updated docs-downloader.bat is missing.
  exit /b 7
)
if not exist "%ROOT%\VERSION" (
  echo [FAIL] Updated VERSION is missing.
  exit /b 7
)

set "VERIFY_VERSION="
set /p VERIFY_VERSION=<"%ROOT%\VERSION"
if /i not "!VERIFY_VERSION!"=="!NEW_VERSION!" (
  echo [FAIL] Update version verification failed.
  exit /b 8
)

echo [INFO] Running updated installer/doctor...
call "%ROOT%\install.bat"
if errorlevel 1 (
  echo [FAIL] Updated files were applied, but install/doctor failed.
  call :rollback
  exit /b 9
)

echo [PASS] Updated Fortinet Docs Downloader to v!VERIFY_VERSION!.
echo [PASS] Existing runtime state and downloaded corpus were preserved.
rmdir /s /q "%WORK%" >nul 2>&1
exit /b 0

:rollback
if not exist "%BACKUP%" exit /b 1
echo [INFO] Restoring previous application files...
robocopy.exe "%BACKUP%" "%ROOT%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
set "ROLLBACK_RC=!ERRORLEVEL!"
if !ROLLBACK_RC! GEQ 8 (
  echo [FAIL] Automatic rollback also failed. Runtime state remains preserved.
  exit /b 1
)
echo [PASS] Previous application files restored. Runtime state was preserved.
exit /b 0
