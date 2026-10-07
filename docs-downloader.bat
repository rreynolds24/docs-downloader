@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "APP_VERSION=0.0.6"
set "BASE_URL=https://docs.fortinet.com"
set "RUNTIME=%~dp0runtime"
set "TEMP_DIR=%RUNTIME%\temp"
set "DOWNLOAD_DIR=%RUNTIME%\downloads"
set "PRODUCT_HTML=%TEMP_DIR%\product.html"
set "DOC_HTML=%TEMP_DIR%\document.html"
set "DOC_LIST=%TEMP_DIR%\documents.txt"\nset "RAW_DOC_LIST=%TEMP_DIR%\documents-raw.txt"
set "PRODUCT_MATCHES=%TEMP_DIR%\product-matches.txt"
set "PDF_MATCHES=%TEMP_DIR%\pdf-matches.txt"

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"

if /i "%~1"=="doctor" goto :doctor
if /i "%~1"=="selftest" goto :selftest
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
echo   1. Download PDFs for a Fortinet product URL
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
set /p "TARGET_URL=Paste Fortinet product URL: "
goto :dispatch

:dispatch
if not defined TARGET_URL (
  echo [FAIL] No URL supplied.
  exit /b 2
)

set "URL_PREFIX=%TARGET_URL:~0,34%"
if /i not "%URL_PREFIX%"=="https://docs.fortinet.com/product/" (
  echo [FAIL] URL must begin with:
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

call :extract_document_links "%PRODUCT_HTML%" "%DOC_LIST%"
if errorlevel 1 (
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

  for %%S in ("!DOC_PATH:/=\!") do set "DOC_SLUG=%%~nxS"

  echo.
  echo [INFO] !TOTAL!: !DOC_SLUG!
  curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "!DOC_URL!" -o "%DOC_HTML%"
  if errorlevel 1 (
    echo [WARN] Could not retrieve document page: !DOC_URL!
    set /a FAILED+=1
  ) else (
    call :extract_pdf_url "%DOC_HTML%"
    if errorlevel 1 (
      echo [WARN] PDF link not found on document page.
      set /a FAILED+=1
    ) else (
      set /a RESOLVED+=1
      for %%F in ("!PDF_URL:/=\!") do set "PDF_NAME=%%~nxF"

      echo [OK]   !PDF_NAME!
      echo        !PDF_URL!

      if /i "!MODE!"=="download" (
        echo [INFO] Downloading...
        curl.exe -L --fail --show-error --progress-bar --connect-timeout 20 --max-time 1800 "!PDF_URL!" -o "%DOWNLOAD_DIR%\!PDF_NAME!"
        if errorlevel 1 (
          echo [WARN] Download failed: !PDF_NAME!
          set /a FAILED+=1
        ) else (
          for %%Z in ("%DOWNLOAD_DIR%\!PDF_NAME!") do (
            if %%~zZ LEQ 0 (
              echo [WARN] Downloaded file is empty: !PDF_NAME!
              set /a FAILED+=1
            ) else (
              echo [OK]   Saved: %DOWNLOAD_DIR%\!PDF_NAME!
            )
          )
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

:extract_document_links
set "SOURCE_HTML=%~1"
set "DEST_LIST=%~2"

findstr /i /c:"/document/" "%SOURCE_HTML%" > "%PRODUCT_MATCHES%"
if errorlevel 1 (
  > "%DEST_LIST%" type nul
  exit /b 1
)

> "%RAW_DOC_LIST%" type nul

for /f usebackq^ tokens^=2^ delims^=^" %%A in ("%PRODUCT_MATCHES%") do (
  set "CANDIDATE=%%A"
  if /i "!CANDIDATE:~0,10!"=="/document/" echo(!CANDIDATE!>>"%RAW_DOC_LIST%"
)
for /f usebackq^ tokens^=4^ delims^=^" %%A in ("%PRODUCT_MATCHES%") do (
  set "CANDIDATE=%%A"
  if /i "!CANDIDATE:~0,10!"=="/document/" echo(!CANDIDATE!>>"%RAW_DOC_LIST%"
)
for /f usebackq^ tokens^=6^ delims^=^" %%A in ("%PRODUCT_MATCHES%") do (
  set "CANDIDATE=%%A"
  if /i "!CANDIDATE:~0,10!"=="/document/" echo(!CANDIDATE!>>"%RAW_DOC_LIST%"
)
for /f usebackq^ tokens^=8^ delims^=^" %%A in ("%PRODUCT_MATCHES%") do (
  set "CANDIDATE=%%A"
  if /i "!CANDIDATE:~0,10!"=="/document/" echo(!CANDIDATE!>>"%RAW_DOC_LIST%"
)
for /f usebackq^ tokens^=10^ delims^=^" %%A in ("%PRODUCT_MATCHES%") do (
  set "CANDIDATE=%%A"
  if /i "!CANDIDATE:~0,10!"=="/document/" echo(!CANDIDATE!>>"%RAW_DOC_LIST%"
)

> "%DEST_LIST%" type nul
for /f "usebackq delims=" %%A in ("%RAW_DOC_LIST%") do (
  set "CANDIDATE=%%A"
  findstr /x /l /c:"!CANDIDATE!" "%DEST_LIST%" >nul 2>&1
  if errorlevel 1 echo(!CANDIDATE!>>"%DEST_LIST%"
)

for %%A in ("%DEST_LIST%") do if %%~zA LEQ 0 exit /b 1
exit /b 0

:extract_pdf_url
set "SOURCE_HTML=%~1"
set "PDF_URL="
> "%PDF_MATCHES%" findstr /i /c:"reader-pdf" "%SOURCE_HTML%"
if errorlevel 1 exit /b 1

set "HAS_READER_ID=0"
for /f usebackq^ tokens^=4^ delims^=^" %%A in ("%PDF_MATCHES%") do (
  if /i "%%A"=="reader-pdf" set "HAS_READER_ID=1"
)

if not "!HAS_READER_ID!"=="1" exit /b 1

for /f usebackq^ tokens^=6^ delims^=^" %%A in ("%PDF_MATCHES%") do (
  set "CANDIDATE=%%A"
  if /i "!CANDIDATE:~0,8!"=="https://" if not defined PDF_URL set "PDF_URL=!CANDIDATE!"
)

if not defined PDF_URL exit /b 1
exit /b 0

:selftest
call :banner
echo.
echo [INFO] Running parser self-test under cmd.exe...

set "FIXTURE_PRODUCT=%~dp0tests\fixtures\product.html"
set "FIXTURE_DOCUMENT=%~dp0tests\fixtures\document.html"
set "SELFTEST_LIST=%TEMP_DIR%\selftest-documents.txt"

if not exist "%FIXTURE_PRODUCT%" (
  echo [FAIL] Missing product fixture.
  exit /b 10
)
if not exist "%FIXTURE_DOCUMENT%" (
  echo [FAIL] Missing document fixture.
  exit /b 10
)

call :extract_document_links "%FIXTURE_PRODUCT%" "%SELFTEST_LIST%"
if errorlevel 1 (
  echo [FAIL] Product fixture parser failed.
  exit /b 11
)

set /a SELFTEST_COUNT=0
set "FIRST_DOC="
for /f "usebackq delims=" %%D in ("%SELFTEST_LIST%") do (
  set /a SELFTEST_COUNT+=1
  if not defined FIRST_DOC set "FIRST_DOC=%%D"
)

if not "!SELFTEST_COUNT!"=="2" (
  echo [FAIL] Expected 2 document links, got !SELFTEST_COUNT!.
  exit /b 12
)

if /i not "!FIRST_DOC!"=="/document/example/7.0/administration-guide" (
  echo [FAIL] First document link was not parsed correctly.
  exit /b 13
)

call :extract_pdf_url "%FIXTURE_DOCUMENT%"
if errorlevel 1 (
  echo [FAIL] Document fixture PDF parser failed.
  exit /b 14
)

if /i not "!PDF_URL!"=="https://fortinetweb.s3.amazonaws.com/docs.fortinet.com/v2/attachments/test/FortiPAM-7.0-Administration_Guide.pdf" (
  echo [FAIL] PDF URL was not parsed correctly.
  exit /b 15
)

echo [PASS] Product document-link parser
echo [PASS] Document reader-pdf parser
echo [PASS] cmd.exe parser self-test
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
echo(
echo(  ### ##### ###     ###################################################
echo( #### ##### ####    ##                                               ##
echo(##### ##### #####   ## Welcome to the Fortinet Docs Downloader       ##
echo(                    ##                                               ##
echo(#####       #####   ###################################################
echo(#####       #####   ##                                               ##
echo(#####       #####   ## Discover and download Fortinet documentation  ##
echo(                    ## directly from docs.fortinet.com                ##
echo(##### ##### #####   ## Windows native: cmd.exe + curl.exe only       ##
echo( #### ##### ####    ## v%APP_VERSION%                                         ##
echo(  ### ##### ###     ###################################################
exit /b 0
