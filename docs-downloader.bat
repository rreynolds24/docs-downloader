@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "APP_VERSION=0.0.1"
set "BASE_URL=https://docs.fortinet.com"
set "RUNTIME=%~dp0runtime"
set "TEMP_DIR=%RUNTIME%\temp"
set "DOWNLOAD_DIR=%RUNTIME%\downloads"
set "PRODUCT_HTML=%TEMP_DIR%\product.html"
set "DOC_HTML=%TEMP_DIR%\document.html"
set "DOC_LIST=%TEMP_DIR%\documents.txt"

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"

if /i "%~1"=="doctor" goto :doctor
if /i "%~1"=="inventory" (
  set "MODE=inventory"
  set "TARGET_URL=%~2"
  goto :dispatch
)
if /i "%~1"=="download" (
  set "MODE=download"
  set "TARGET_URL=%~2"
  goto :dispatch
)
if not "%~1"=="" (
  set "MODE=download"
  set "TARGET_URL=%~1"
  goto :dispatch
)

:menu
cls
call :banner
echo.
echo   1. Download PDFs for a Fortinet product/version URL
echo   2. Inventory PDFs without downloading
echo   3. Doctor / environment check
echo   4. Exit
echo.
set /p "CHOICE=Select an option: "
if "%CHOICE%"=="1" (
  set "MODE=download"
  set "TARGET_URL="
  goto :prompt_url
)
if "%CHOICE%"=="2" (
  set "MODE=inventory"
  set "TARGET_URL="
  goto :prompt_url
)
if "%CHOICE%"=="3" goto :doctor_menu
if "%CHOICE%"=="4" exit /b 0
goto :menu

:prompt_url
echo.
set /p "TARGET_URL=Paste Fortinet product/version URL: "
goto :dispatch

:dispatch
if not defined TARGET_URL (
  echo [FAIL] No URL supplied.
  exit /b 2
)

echo "%TARGET_URL%" | findstr /i /b /c:"https://docs.fortinet.com/product/" >nul
if errorlevel 1 (
  echo [FAIL] v0.0.1 accepts product/version URLs beginning with:
  echo        https://docs.fortinet.com/product/
  exit /b 2
)

call :doctor_quiet
if errorlevel 1 exit /b 1

call :banner
echo.
echo [INFO] Fetching product page...
curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "%TARGET_URL%" -o "%PRODUCT_HTML%"
if errorlevel 1 (
  echo [FAIL] Could not retrieve the Fortinet product page.
  exit /b 3
)

> "%DOC_LIST%" (
  for /f "usebackq tokens=2 delims=^"" %%A in (`findstr /i /c:"^<a href=^"/document/" "%PRODUCT_HTML%"`) do (
    echo %%A
  )
)

for %%A in ("%DOC_LIST%") do if %%~zA==0 (
  echo [FAIL] No document links were discovered on the product page.
  echo        Fortinet may have changed the page structure.
  exit /b 4
)

echo.
echo [INFO] Resolving PDF targets...
set /a TOTAL=0
set /a RESOLVED=0
set /a FAILED=0

for /f "usebackq delims=" %%D in ("%DOC_LIST%") do (
  set /a TOTAL+=1
  set "DOC_PATH=%%D"
  set "DOC_URL=%BASE_URL%!DOC_PATH!"
  set "PDF_URL="
  set "PDF_NAME="
  set "DOC_SLUG="

  for %%S in (!DOC_PATH:/= !) do set "DOC_SLUG=%%S"

  echo.
  echo [INFO] !TOTAL!: !DOC_SLUG!
  curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "!DOC_URL!" -o "%DOC_HTML%"
  if errorlevel 1 (
    echo [WARN] Could not retrieve document page: !DOC_URL!
    set /a FAILED+=1
  ) else (
    for /f "usebackq tokens=6 delims=^"" %%P in (`findstr /i /c:"id=^"reader-pdf^"" "%DOC_HTML%"`) do (
      if not defined PDF_URL set "PDF_URL=%%P"
    )

    if not defined PDF_URL (
      echo [WARN] PDF link not found on document page.
      set /a FAILED+=1
    ) else (
      set /a RESOLVED+=1
      for %%F in (!PDF_URL:/= !) do set "PDF_NAME=%%F"

      echo [OK]   !PDF_NAME!
      echo        !PDF_URL!

      if /i "!MODE!"=="download" (
        echo [INFO] Downloading...
        curl.exe -L --fail --show-error --progress-bar --connect-timeout 20 --max-time 1800 "!PDF_URL!" -o "%DOWNLOAD_DIR%\!PDF_NAME!"
        if errorlevel 1 (
          echo [WARN] Download failed: !PDF_NAME!
          set /a FAILED+=1
        ) else (
          echo [OK]   Saved: %DOWNLOAD_DIR%\!PDF_NAME!
        )
      )
    )
  )
)

echo.
echo ------------------------------------------------------------
echo Documents discovered : !TOTAL!
echo PDF targets resolved  : !RESOLVED!
echo Warnings/failures     : !FAILED!
if /i "!MODE!"=="download" echo Download directory    : %DOWNLOAD_DIR%
echo ------------------------------------------------------------

if !RESOLVED! EQU 0 exit /b 5
if !FAILED! GTR 0 exit /b 6
exit /b 0

:doctor_menu
call :doctor
echo.
pause
goto :menu

:doctor
call :banner
echo.
call :doctor_quiet
exit /b %errorlevel%

:doctor_quiet
set "DOCTOR_FAIL=0"

where cmd.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] cmd.exe
  set "DOCTOR_FAIL=1"
) else echo [PASS] cmd.exe

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe
  set "DOCTOR_FAIL=1"
) else echo [PASS] curl.exe

where findstr.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] findstr.exe
  set "DOCTOR_FAIL=1"
) else echo [PASS] findstr.exe

if exist "%TEMP_DIR%" (
  echo [PASS] runtime\temp
) else (
  mkdir "%TEMP_DIR%" >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] runtime\temp
    set "DOCTOR_FAIL=1"
  ) else echo [PASS] runtime\temp
)

if exist "%DOWNLOAD_DIR%" (
  echo [PASS] runtime\downloads
) else (
  mkdir "%DOWNLOAD_DIR%" >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] runtime\downloads
    set "DOCTOR_FAIL=1"
  ) else echo [PASS] runtime\downloads
)

if "%DOCTOR_FAIL%"=="1" exit /b 1
exit /b 0

:banner
echo.
echo   ### ##### ###     ###################################################
echo  #### ##### ####    ##                                               ##
echo ##### ##### #####   ## Welcome to the Fortinet Docs Downloader       ##
echo                     ##                                               ##
echo #####       #####   ###################################################
echo #####       #####   ##                                               ##
echo #####       #####   ## Discover and download Fortinet documentation  ##
echo                     ## directly from docs.fortinet.com                ##
echo ##### ##### #####   ## Windows native: cmd.exe + curl.exe only       ##
echo  #### ##### ####    ## v%APP_VERSION%                                         ##
echo   ### ##### ###     ###################################################
exit /b 0
