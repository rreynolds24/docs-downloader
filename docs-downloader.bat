@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "APP_VERSION=0.0.7"
set "BASE_URL=https://docs.fortinet.com"
set "RUNTIME=%~dp0runtime"
set "TEMP_DIR=%RUNTIME%\temp"
set "DOWNLOAD_DIR=%RUNTIME%\downloads"
set "STATE_DIR=%RUNTIME%\state"
set "MANIFEST=%STATE_DIR%\downloads.db"
set "MANIFEST_TMP=%TEMP_DIR%\downloads-db.tmp"
set "HEADER_FILE=%TEMP_DIR%\pdf-headers.txt"
set "PRODUCT_HTML=%TEMP_DIR%\product.html"
set "DOC_HTML=%TEMP_DIR%\document.html"
set "DOC_LIST=%TEMP_DIR%\documents.txt"
set "RAW_DOC_LIST=%TEMP_DIR%\documents-raw.txt"
set "PRODUCT_MATCHES=%TEMP_DIR%\product-matches.txt"
set "PDF_MATCHES=%TEMP_DIR%\pdf-matches.txt"

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%"
if not exist "%MANIFEST%" type nul > "%MANIFEST%"

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
set /a NO_PDF=0
set /a NEW_COUNT=0
set /a CHANGED_COUNT=0
set /a UNCHANGED_COUNT=0
set /a MISSING_COUNT=0
set /a DOWNLOADED_COUNT=0
set /a SKIPPED_COUNT=0

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
      echo [INFO] No PDF available for this document; skipping.
      set /a NO_PDF+=1
    ) else (
      set /a RESOLVED+=1
      for %%F in ("!PDF_URL:/=\!") do set "PDF_NAME=%%~nxF"

      call :get_remote_etag "!PDF_URL!"
      call :classify_download "!DOC_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!"

      echo [!TRACK_STATUS!] !PDF_NAME!
      echo        !PDF_URL!

      if /i "!TRACK_STATUS!"=="NEW" set /a NEW_COUNT+=1
      if /i "!TRACK_STATUS!"=="CHANGED" set /a CHANGED_COUNT+=1
      if /i "!TRACK_STATUS!"=="UNCHANGED" set /a UNCHANGED_COUNT+=1
      if /i "!TRACK_STATUS!"=="MISSING_LOCAL" set /a MISSING_COUNT+=1

      if /i "!MODE!"=="download" (
        if /i "!TRACK_STATUS!"=="UNCHANGED" (
          echo [INFO] Already downloaded and unchanged; skipping.
          set /a SKIPPED_COUNT+=1
        ) else (
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
                call :write_manifest "!DOC_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!"
                if errorlevel 1 (
                  echo [WARN] Download succeeded but tracking state could not be updated.
                  set /a FAILED+=1
                ) else (
                  set /a DOWNLOADED_COUNT+=1
                  echo [OK]   Saved and tracked: %DOWNLOAD_DIR%\!PDF_NAME!
                )
              )
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
echo No PDF available      : !NO_PDF!
echo New PDFs              : !NEW_COUNT!
echo Changed PDFs          : !CHANGED_COUNT!
echo Unchanged PDFs        : !UNCHANGED_COUNT!
echo Missing local PDFs    : !MISSING_COUNT!
if /i "!MODE!"=="download" echo Downloaded/updated     : !DOWNLOADED_COUNT!
if /i "!MODE!"=="download" echo Unchanged/skipped     : !SKIPPED_COUNT!
echo Warnings/failures     : !FAILED!
if /i "!MODE!"=="download" echo Download directory    : %DOWNLOAD_DIR%
echo Tracking database     : %MANIFEST%
echo ------------------------------------------------------------

if !RESOLVED! EQU 0 exit /b 5
if !FAILED! GTR 0 exit /b 6
exit /b 0

:get_remote_etag
set "REMOTE_ETAG="
curl.exe -L --fail --silent --show-error --head --connect-timeout 20 --max-time 120 "%~1" -o "%HEADER_FILE%" >nul 2>&1
if errorlevel 1 exit /b 0
for /f "tokens=1,* delims=:" %%A in ('findstr /i /b /c:"ETag:" "%HEADER_FILE%"') do (
  set "REMOTE_ETAG=%%B"
)
for /f "tokens=* delims= " %%A in ("!REMOTE_ETAG!") do set "REMOTE_ETAG=%%A"
set "REMOTE_ETAG=!REMOTE_ETAG:"=!"
exit /b 0

:classify_download
set "TRACK_STATUS=NEW"
set "CURRENT_ETAG=%~4"
set "PREV_PDF_URL="
set "PREV_PDF_NAME="
set "PREV_ETAG="

call :lookup_manifest "%~1"
if errorlevel 1 exit /b 0

if /i not "!PREV_PDF_URL!"=="%~2" (
  set "TRACK_STATUS=CHANGED"
  exit /b 0
)
if /i not "!PREV_PDF_NAME!"=="%~3" (
  set "TRACK_STATUS=CHANGED"
  exit /b 0
)
if defined CURRENT_ETAG (
  if not defined PREV_ETAG (
    set "TRACK_STATUS=CHANGED"
    exit /b 0
  )
  if /i not "!PREV_ETAG!"=="!CURRENT_ETAG!" (
    set "TRACK_STATUS=CHANGED"
    exit /b 0
  )
)
if not exist "%DOWNLOAD_DIR%\!PREV_PDF_NAME!" (
  set "TRACK_STATUS=MISSING_LOCAL"
  exit /b 0
)
set "TRACK_STATUS=UNCHANGED"
exit /b 0

:lookup_manifest
set "PREV_PDF_URL="
set "PREV_PDF_NAME="
set "PREV_ETAG="
if not exist "%MANIFEST%" exit /b 1
for /f "usebackq tokens=1,2,3,4 delims=|" %%A in ("%MANIFEST%") do (
  if /i "%%A"=="%~1" (
    set "PREV_PDF_URL=%%B"
    set "PREV_PDF_NAME=%%C"
    set "PREV_ETAG=%%D"
    exit /b 0
  )
)
exit /b 1

:write_manifest
> "%MANIFEST_TMP%" (
  if exist "%MANIFEST%" (
    for /f "usebackq tokens=1,* delims=|" %%A in ("%MANIFEST%") do (
      if /i not "%%A"=="%~1" echo(%%A^|%%B
    )
  )
  echo(%~1^|%~2^|%~3^|%~4
)
move /y "%MANIFEST_TMP%" "%MANIFEST%" >nul
if errorlevel 1 exit /b 1
exit /b 0

:extract_document_links
set "SOURCE_HTML=%~1"
set "DEST_LIST=%~2"

findstr /i /c:"<a " "%SOURCE_HTML%" | findstr /i /c:"/document/" > "%PRODUCT_MATCHES%"
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

if not "!SELFTEST_COUNT!"=="3" (
  echo [FAIL] Expected 3 unique document links, got !SELFTEST_COUNT!.
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

set "ORIGINAL_MANIFEST=%MANIFEST%"
set "ORIGINAL_DOWNLOAD_DIR=%DOWNLOAD_DIR%"
set "MANIFEST=%TEMP_DIR%\selftest-downloads.db"
set "DOWNLOAD_DIR=%TEMP_DIR%\selftest-downloads"
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"
> "%MANIFEST%" type nul
> "%DOWNLOAD_DIR%\sample.pdf" echo test

call :write_manifest "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-one"
if errorlevel 1 (
  echo [FAIL] Tracking manifest write failed.
  exit /b 16
)

call :classify_download "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-one"
if /i not "!TRACK_STATUS!"=="UNCHANGED" (
  echo [FAIL] Tracking expected UNCHANGED, got !TRACK_STATUS!.
  exit /b 17
)

call :classify_download "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-two"
if /i not "!TRACK_STATUS!"=="CHANGED" (
  echo [FAIL] Tracking expected CHANGED, got !TRACK_STATUS!.
  exit /b 18
)

del /q "%DOWNLOAD_DIR%\sample.pdf" >nul 2>&1
call :classify_download "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-one"
if /i not "!TRACK_STATUS!"=="MISSING_LOCAL" (
  echo [FAIL] Tracking expected MISSING_LOCAL, got !TRACK_STATUS!.
  exit /b 19
)

call :classify_download "https://docs.fortinet.com/document/example/1.0/new" "https://example.test/new.pdf" "new.pdf" "etag-new"
if /i not "!TRACK_STATUS!"=="NEW" (
  echo [FAIL] Tracking expected NEW, got !TRACK_STATUS!.
  exit /b 20
)

set "MANIFEST=%ORIGINAL_MANIFEST%"
set "DOWNLOAD_DIR=%ORIGINAL_DOWNLOAD_DIR%"
del /q "%TEMP_DIR%\selftest-downloads.db" >nul 2>&1
rmdir /s /q "%TEMP_DIR%\selftest-downloads" >nul 2>&1

echo [PASS] Download tracking classifications
echo [PASS] cmd.exe parser and tracking self-test
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

if exist "%STATE_DIR%" (
  echo [PASS] runtime\state
) else (
  mkdir "%STATE_DIR%" >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] runtime\state
    set "DOCTOR_FAIL=1"
  ) else echo [PASS] runtime\state
)

if not exist "%MANIFEST%" (
  type nul > "%MANIFEST%" 2>nul
  if errorlevel 1 (
    echo [FAIL] tracking database
    set "DOCTOR_FAIL=1"
  ) else echo [PASS] tracking database
) else echo [PASS] tracking database

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
