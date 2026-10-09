@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "APP_VERSION=0.0.8"
set "BASE_URL=https://docs.fortinet.com"
set "RUNTIME=%~dp0runtime"
set "TEMP_DIR=%RUNTIME%\temp"
set "DOWNLOAD_DIR=%RUNTIME%\downloads"
set "STATE_DIR=%RUNTIME%\state"
set "MANIFEST=%STATE_DIR%\downloads.db"
set "CATALOGUE=%STATE_DIR%\catalogue.db"
set "MANIFEST_TMP=%TEMP_DIR%\downloads-db.tmp"
set "CATALOGUE_TMP=%TEMP_DIR%\catalogue-db.tmp"
set "HEADER_FILE=%TEMP_DIR%\pdf-headers.txt"
set "DOWNLOAD_TMP=%TEMP_DIR%\download.tmp"
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
if not exist "%CATALOGUE%" type nul > "%CATALOGUE%"

if /i "%~1"=="doctor" goto :doctor
if /i "%~1"=="selftest" goto :selftest
if /i "%~1"=="inventory" (
  set "MODE=inventory"
  set "TARGET_URL=%~2"
  goto :dispatch
)
if /i "%~1"=="check" (
  set "MODE=check"
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
echo   1. Download/synchronize PDFs
echo   2. Inventory PDFs without downloading
echo   3. Check for new or changed document versions
echo   4. Doctor / environment check
echo   5. Exit
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
if "%CHOICE%"=="3" (
  set "MODE=check"
  set "TARGET_URL="
  goto :prompt_url
)
if "%CHOICE%"=="4" goto :doctor_menu
if "%CHOICE%"=="5" exit /b 0
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

set "RUN_SEEN=%DATE%T%TIME%"

call :banner
echo.
if /i "%MODE%"=="check" echo [INFO] Checking live catalogue for new or changed versions...
if /i not "%MODE%"=="check" echo [INFO] Fetching product page...
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
echo [INFO] Resolving PDF targets and version metadata...
set /a TOTAL=0
set /a RESOLVED=0
set /a FAILED=0
set /a NO_PDF=0

set /a NEW_COUNT=0
set /a CHANGED_COUNT=0
set /a UNCHANGED_COUNT=0
set /a MISSING_COUNT=0

set /a NEW_DOCUMENT_COUNT=0
set /a NEW_VERSION_COUNT=0
set /a UPDATED_IN_PLACE_COUNT=0
set /a KNOWN_VERSION_COUNT=0
set /a AVAILABLE_COUNT=0
set /a DUPLICATE_COUNT=0

set /a DOWNLOADED_COUNT=0
set /a SKIPPED_COUNT=0
set /a DEDUPED_COUNT=0

for /f "usebackq delims=" %%D in ("%DOC_LIST%") do (
  set /a TOTAL+=1
  set "DOC_PATH=%%D"
  set "DOC_URL=%BASE_URL%!DOC_PATH!"
  set "PDF_URL="
  set "PDF_NAME="
  set "DOC_SLUG="
  set "FILE_HASH=-"
  set "LOCAL_NAME=-"
  set "CONTENT_DUPLICATE=0"

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

      call :get_remote_metadata "!PDF_URL!"
      call :parse_doc_identity "!DOC_PATH!" "!PDF_NAME!"
      call :classify_download "!DOC_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!"
      call :classify_version "!DOC_URL!" "!TRACK_STATUS!"

      echo [!VERSION_STATUS!][!TRACK_STATUS!] !PDF_NAME!
      echo        product=!PRODUCT_ID! family=!DOC_FAMILY! version=!DOC_VERSION!
      echo        !PDF_URL!

      if /i "!TRACK_STATUS!"=="NEW" set /a NEW_COUNT+=1
      if /i "!TRACK_STATUS!"=="CHANGED" set /a CHANGED_COUNT+=1
      if /i "!TRACK_STATUS!"=="UNCHANGED" set /a UNCHANGED_COUNT+=1
      if /i "!TRACK_STATUS!"=="MISSING_LOCAL" set /a MISSING_COUNT+=1

      if /i "!VERSION_STATUS!"=="NEW_DOCUMENT" set /a NEW_DOCUMENT_COUNT+=1
      if /i "!VERSION_STATUS!"=="NEW_VERSION" set /a NEW_VERSION_COUNT+=1
      if /i "!VERSION_STATUS!"=="UPDATED_IN_PLACE" set /a UPDATED_IN_PLACE_COUNT+=1
      if /i "!VERSION_STATUS!"=="KNOWN_VERSION" set /a KNOWN_VERSION_COUNT+=1
      if /i "!VERSION_STATUS!"=="AVAILABLE_NOT_DOWNLOADED" set /a AVAILABLE_COUNT+=1

      if /i "!MODE!"=="download" (
        if /i "!TRACK_STATUS!"=="UNCHANGED" (
          set "LOCAL_NAME=!PREV_LOCAL_NAME!"
          if not defined LOCAL_NAME set "LOCAL_NAME=!PREV_PDF_NAME!"
          if "!LOCAL_NAME!"=="" set "LOCAL_NAME=!PREV_PDF_NAME!"
          if exist "%DOWNLOAD_DIR%\!LOCAL_NAME!" (
            call :compute_sha256 "%DOWNLOAD_DIR%\!LOCAL_NAME!"
          )
          if not defined FILE_HASH set "FILE_HASH=-"
          call :write_catalogue_current "CURRENT"
          set /a SKIPPED_COUNT+=1
          echo [INFO] Already downloaded and unchanged; skipping.
        ) else (
          call :lookup_duplicate_remote "!PDF_URL!" "!REMOTE_ETAG!" "!REMOTE_LENGTH!"
          if "!DUP_FOUND!"=="1" (
            set "FILE_HASH=!DUP_SHA!"
            set "LOCAL_NAME=!DUP_LOCAL!"
            if "!FILE_HASH!"=="-" call :compute_sha256 "%DOWNLOAD_DIR%\!LOCAL_NAME!"
            call :write_manifest "!DOC_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!" "!LOCAL_NAME!"
            if errorlevel 1 (
              echo [WARN] Duplicate was identified but tracking state could not be updated.
              set /a FAILED+=1
            ) else (
              call :write_catalogue_current "CURRENT"
              set /a DUPLICATE_COUNT+=1
              set /a DEDUPED_COUNT+=1
              echo [DUPLICATE_CONTENT] Reusing existing local file: !LOCAL_NAME!
            )
          ) else (
            if exist "%DOWNLOAD_TMP%" del /q "%DOWNLOAD_TMP%" >nul 2>&1
            echo [INFO] Downloading candidate content...
            curl.exe -L --fail --show-error --progress-bar --connect-timeout 20 --max-time 1800 "!PDF_URL!" -o "%DOWNLOAD_TMP%"
            if errorlevel 1 (
              echo [WARN] Download failed: !PDF_NAME!
              set /a FAILED+=1
            ) else (
              for %%Z in ("%DOWNLOAD_TMP%") do (
                if %%~zZ LEQ 0 (
                  echo [WARN] Downloaded file is empty: !PDF_NAME!
                  set /a FAILED+=1
                ) else (
                  call :compute_sha256 "%DOWNLOAD_TMP%"
                  if not defined FILE_HASH (
                    echo [WARN] Could not compute SHA-256 for downloaded content.
                    set /a FAILED+=1
                  ) else (
                    call :lookup_duplicate_hash "!FILE_HASH!"
                    if "!DUP_FOUND!"=="1" (
                      set "LOCAL_NAME=!DUP_LOCAL!"
                      del /q "%DOWNLOAD_TMP%" >nul 2>&1
                      call :write_manifest "!DOC_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!" "!LOCAL_NAME!"
                      if errorlevel 1 (
                        echo [WARN] Duplicate content found but tracking state could not be updated.
                        set /a FAILED+=1
                      ) else (
                        call :write_catalogue_current "CURRENT"
                        set /a DUPLICATE_COUNT+=1
                        set /a DEDUPED_COUNT+=1
                        echo [DUPLICATE_CONTENT] SHA-256 matches existing local file: !LOCAL_NAME!
                      )
                    ) else (
                      call :choose_local_name "!PDF_NAME!" "!FILE_HASH!"
                      if "!CONTENT_ALREADY_LOCAL!"=="1" (
                        del /q "%DOWNLOAD_TMP%" >nul 2>&1
                        set /a DUPLICATE_COUNT+=1
                        set /a DEDUPED_COUNT+=1
                      ) else (
                        move /y "%DOWNLOAD_TMP%" "%DOWNLOAD_DIR%\!LOCAL_NAME!" >nul
                        if errorlevel 1 (
                          echo [WARN] Could not move downloaded PDF into the download directory.
                          set /a FAILED+=1
                        ) else (
                          set /a DOWNLOADED_COUNT+=1
                        )
                      )

                      if not errorlevel 1 (
                        call :write_manifest "!DOC_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!" "!LOCAL_NAME!"
                        if errorlevel 1 (
                          echo [WARN] Download succeeded but tracking state could not be updated.
                          set /a FAILED+=1
                        ) else (
                          call :write_catalogue_current "CURRENT"
                          if "!CONTENT_ALREADY_LOCAL!"=="1" (
                            echo [DUPLICATE_CONTENT] Existing local bytes reused: !LOCAL_NAME!
                          ) else (
                            echo [OK]   Saved and catalogued: %DOWNLOAD_DIR%\!LOCAL_NAME!
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      ) else (
        if /i "!TRACK_STATUS!"=="UNCHANGED" (
          set "LOCAL_NAME=!PREV_LOCAL_NAME!"
          if not defined LOCAL_NAME set "LOCAL_NAME=!PREV_PDF_NAME!"
          if exist "%DOWNLOAD_DIR%\!LOCAL_NAME!" call :compute_sha256 "%DOWNLOAD_DIR%\!LOCAL_NAME!"
          if not defined FILE_HASH set "FILE_HASH=-"
          call :write_catalogue_current "CURRENT"
        ) else (
          call :lookup_duplicate_remote "!PDF_URL!" "!REMOTE_ETAG!" "!REMOTE_LENGTH!"
          if "!DUP_FOUND!"=="1" (
            set "FILE_HASH=!DUP_SHA!"
            set "LOCAL_NAME=!DUP_LOCAL!"
            set /a DUPLICATE_COUNT+=1
            echo [DUPLICATE_CONTENT] Existing content is already stored as !LOCAL_NAME!
            call :write_catalogue_current "CURRENT"
          ) else (
            set "FILE_HASH=-"
            set "LOCAL_NAME=-"
            call :write_catalogue_current "AVAILABLE"
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
echo.
echo New documents         : !NEW_DOCUMENT_COUNT!
echo New versions          : !NEW_VERSION_COUNT!
echo Updated in place      : !UPDATED_IN_PLACE_COUNT!
echo Known versions        : !KNOWN_VERSION_COUNT!
echo Available/not local   : !AVAILABLE_COUNT!
echo Duplicate content     : !DUPLICATE_COUNT!
echo.
echo New PDFs              : !NEW_COUNT!
echo Changed PDFs          : !CHANGED_COUNT!
echo Unchanged PDFs        : !UNCHANGED_COUNT!
echo Missing local PDFs    : !MISSING_COUNT!
if /i "!MODE!"=="download" echo Downloaded/updated     : !DOWNLOADED_COUNT!
if /i "!MODE!"=="download" echo Unchanged/skipped     : !SKIPPED_COUNT!
if /i "!MODE!"=="download" echo Duplicate downloads avoided: !DEDUPED_COUNT!
echo Warnings/failures     : !FAILED!
if /i "!MODE!"=="download" echo Download directory    : %DOWNLOAD_DIR%
echo Tracking database     : %MANIFEST%
echo Version catalogue     : %CATALOGUE%
echo ------------------------------------------------------------

if !RESOLVED! EQU 0 exit /b 5
if !FAILED! GTR 0 exit /b 6
exit /b 0

:get_remote_metadata
set "REMOTE_ETAG=-"
set "REMOTE_LENGTH=-"
curl.exe -L --fail --silent --show-error --head --connect-timeout 20 --max-time 120 "%~1" -o "%HEADER_FILE%" >nul 2>&1
if errorlevel 1 exit /b 0

for /f "tokens=1,* delims=:" %%A in ('findstr /i /b /c:"ETag:" "%HEADER_FILE%"') do set "REMOTE_ETAG=%%B"
for /f "tokens=1,* delims=:" %%A in ('findstr /i /b /c:"Content-Length:" "%HEADER_FILE%"') do set "REMOTE_LENGTH=%%B"

for /f "tokens=* delims= " %%A in ("!REMOTE_ETAG!") do set "REMOTE_ETAG=%%A"
for /f "tokens=* delims= " %%A in ("!REMOTE_LENGTH!") do set "REMOTE_LENGTH=%%A"

set "REMOTE_ETAG=!REMOTE_ETAG:"=!"
if not defined REMOTE_ETAG set "REMOTE_ETAG=-"
if not defined REMOTE_LENGTH set "REMOTE_LENGTH=-"
exit /b 0

:parse_doc_identity
set "PRODUCT_ID=unknown"
set "SOURCE_VERSION=unknown"
set "DOC_FAMILY=unknown"
set "DOC_VERSION=unknown"

for /f "tokens=2,3,4 delims=/" %%A in ("%~1") do (
  set "PRODUCT_ID=%%A"
  set "SOURCE_VERSION=%%B"
  set "DOC_FAMILY=%%C"
)
set "DOC_VERSION=!SOURCE_VERSION!"
if /i "!SOURCE_VERSION!"=="latest" (
  call :infer_version_from_filename "%~2"
  if defined INFERRED_VERSION set "DOC_VERSION=!INFERRED_VERSION!"
)
exit /b 0

:infer_version_from_filename
set "INFERRED_VERSION="
set "VERSION_SCAN=%~1"
set "VERSION_SCAN=!VERSION_SCAN:_= !"
set "VERSION_SCAN=!VERSION_SCAN:-= !"
for %%V in (!VERSION_SCAN!) do (
  set "VERSION_TOKEN=%%V"
  if /i "!VERSION_TOKEN:~0,1!"=="v" set "VERSION_TOKEN=!VERSION_TOKEN:~1!"
  set "NON_VERSION_CHARS="
  for /f "delims=0123456789." %%X in ("!VERSION_TOKEN!") do set "NON_VERSION_CHARS=%%X"
  if not defined NON_VERSION_CHARS (
    if not "!VERSION_TOKEN:.=!"=="!VERSION_TOKEN!" (
      if not defined INFERRED_VERSION set "INFERRED_VERSION=!VERSION_TOKEN!"
    )
  )
)
exit /b 0

:classify_download
set "TRACK_STATUS=NEW"
set "CURRENT_ETAG=%~4"
set "PREV_PDF_URL="
set "PREV_PDF_NAME="
set "PREV_ETAG="
set "PREV_LOCAL_NAME="

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
if not "%~4"=="-" (
  if "!PREV_ETAG!"=="" (
    set "TRACK_STATUS=CHANGED"
    exit /b 0
  )
  if "!PREV_ETAG!"=="-" (
    set "TRACK_STATUS=CHANGED"
    exit /b 0
  )
  if /i not "!PREV_ETAG!"=="%~4" (
    set "TRACK_STATUS=CHANGED"
    exit /b 0
  )
)
if not defined PREV_LOCAL_NAME set "PREV_LOCAL_NAME=!PREV_PDF_NAME!"
if not exist "%DOWNLOAD_DIR%\!PREV_LOCAL_NAME!" (
  set "TRACK_STATUS=MISSING_LOCAL"
  exit /b 0
)
set "TRACK_STATUS=UNCHANGED"
exit /b 0

:lookup_manifest
set "PREV_PDF_URL="
set "PREV_PDF_NAME="
set "PREV_ETAG="
set "PREV_LOCAL_NAME="
if not exist "%MANIFEST%" exit /b 1
for /f "usebackq tokens=1,2,3,4,5 delims=|" %%A in ("%MANIFEST%") do (
  if /i "%%A"=="%~1" (
    set "PREV_PDF_URL=%%B"
    set "PREV_PDF_NAME=%%C"
    set "PREV_ETAG=%%D"
    set "PREV_LOCAL_NAME=%%E"
    if not defined PREV_LOCAL_NAME set "PREV_LOCAL_NAME=%%C"
    exit /b 0
  )
)
exit /b 1

:write_manifest
set "WRITE_ETAG=%~4"
if not defined WRITE_ETAG set "WRITE_ETAG=-"
set "WRITE_LOCAL=%~5"
if not defined WRITE_LOCAL set "WRITE_LOCAL=%~3"
> "%MANIFEST_TMP%" (
  if exist "%MANIFEST%" (
    for /f "usebackq tokens=1,* delims=|" %%A in ("%MANIFEST%") do (
      if /i not "%%A"=="%~1" echo(%%A^|%%B
    )
  )
  echo(%~1^|%~2^|%~3^|!WRITE_ETAG!^|!WRITE_LOCAL!
)
move /y "%MANIFEST_TMP%" "%MANIFEST%" >nul
if errorlevel 1 exit /b 1
exit /b 0

:classify_version
set "VERSION_STATUS=KNOWN_VERSION"
call :lookup_catalogue_active "%~1"
if not errorlevel 1 (
  if /i "!CAT_STATUS!"=="AVAILABLE" (
    set "VERSION_STATUS=AVAILABLE_NOT_DOWNLOADED"
    exit /b 0
  )
  if /i "%~2"=="CHANGED" (
    set "VERSION_STATUS=UPDATED_IN_PLACE"
    exit /b 0
  )
  set "VERSION_STATUS=KNOWN_VERSION"
  exit /b 0
)

call :family_seen "!PRODUCT_ID!" "!DOC_FAMILY!"
if errorlevel 1 (
  set "VERSION_STATUS=NEW_DOCUMENT"
  exit /b 0
)
call :family_version_seen "!PRODUCT_ID!" "!DOC_FAMILY!" "!DOC_VERSION!"
if errorlevel 1 (
  set "VERSION_STATUS=NEW_VERSION"
  exit /b 0
)
if /i "%~2"=="CHANGED" set "VERSION_STATUS=UPDATED_IN_PLACE"
exit /b 0

:lookup_catalogue_active
set "CAT_FOUND=0"
set "CAT_PDF_URL="
set "CAT_REMOTE_NAME="
set "CAT_ETAG="
set "CAT_LENGTH="
set "CAT_SHA="
set "CAT_LOCAL="
set "CAT_STATUS="
if not exist "%CATALOGUE%" exit /b 1
for /f "usebackq tokens=1-15 delims=|" %%A in ("%CATALOGUE%") do (
  if /i "%%A"=="%~1" (
    if /i "%%N"=="CURRENT" (
      set "CAT_FOUND=1"
      set "CAT_PDF_URL=%%F"
      set "CAT_REMOTE_NAME=%%G"
      set "CAT_ETAG=%%H"
      set "CAT_LENGTH=%%I"
      set "CAT_SHA=%%J"
      set "CAT_LOCAL=%%M"
      set "CAT_STATUS=%%N"
      exit /b 0
    )
    if /i "%%N"=="AVAILABLE" (
      set "CAT_FOUND=1"
      set "CAT_PDF_URL=%%F"
      set "CAT_REMOTE_NAME=%%G"
      set "CAT_ETAG=%%H"
      set "CAT_LENGTH=%%I"
      set "CAT_SHA=%%J"
      set "CAT_LOCAL=%%M"
      set "CAT_STATUS=%%N"
      exit /b 0
    )
  )
)
exit /b 1

:family_seen
if not exist "%CATALOGUE%" exit /b 1
for /f "usebackq tokens=2,3 delims=|" %%A in ("%CATALOGUE%") do (
  if /i "%%A"=="%~1" if /i "%%B"=="%~2" exit /b 0
)
exit /b 1

:family_version_seen
if not exist "%CATALOGUE%" exit /b 1
for /f "usebackq tokens=2,3,5 delims=|" %%A in ("%CATALOGUE%") do (
  if /i "%%A"=="%~1" if /i "%%B"=="%~2" if /i "%%C"=="%~3" exit /b 0
)
exit /b 1

:lookup_duplicate_remote
set "DUP_FOUND=0"
set "DUP_LOCAL="
set "DUP_SHA=-"
set "CURRENT_PDF_URL=%~1"
set "CURRENT_REMOTE_ETAG=%~2"
set "CURRENT_REMOTE_LENGTH=%~3"
if not exist "%CATALOGUE%" exit /b 1
for /f "usebackq tokens=1-15 delims=|" %%A in ("%CATALOGUE%") do (
  set "ROW_PDF_URL=%%F"
  set "ROW_ETAG=%%H"
  set "ROW_LENGTH=%%I"
  set "ROW_SHA=%%J"
  set "ROW_LOCAL=%%M"
  if not "!ROW_LOCAL!"=="-" (
    if exist "%DOWNLOAD_DIR%\!ROW_LOCAL!" (
      if /i "!ROW_PDF_URL!"=="!CURRENT_PDF_URL!" (
        set "REMOTE_CONFLICT=0"
        if not "!CURRENT_REMOTE_ETAG!"=="-" if not "!ROW_ETAG!"=="-" if /i not "!ROW_ETAG!"=="!CURRENT_REMOTE_ETAG!" set "REMOTE_CONFLICT=1"
        if not "!CURRENT_REMOTE_LENGTH!"=="-" if not "!ROW_LENGTH!"=="-" if /i not "!ROW_LENGTH!"=="!CURRENT_REMOTE_LENGTH!" set "REMOTE_CONFLICT=1"
        if "!REMOTE_CONFLICT!"=="0" (
          set "DUP_FOUND=1"
          set "DUP_LOCAL=!ROW_LOCAL!"
          set "DUP_SHA=!ROW_SHA!"
          exit /b 0
        )
      )
      if not "!CURRENT_REMOTE_ETAG!"=="-" if not "!CURRENT_REMOTE_LENGTH!"=="-" (
        if /i "!ROW_ETAG!"=="!CURRENT_REMOTE_ETAG!" if /i "!ROW_LENGTH!"=="!CURRENT_REMOTE_LENGTH!" (
          set "DUP_FOUND=1"
          set "DUP_LOCAL=!ROW_LOCAL!"
          set "DUP_SHA=!ROW_SHA!"
          exit /b 0
        )
      )
    )
  )
)
exit /b 1

:lookup_duplicate_hash
set "DUP_FOUND=0"
set "DUP_LOCAL="
set "DUP_SHA=-"
if not exist "%CATALOGUE%" exit /b 1
for /f "usebackq tokens=10,13 delims=|" %%A in ("%CATALOGUE%") do (
  if /i "%%A"=="%~1" (
    if not "%%B"=="-" if exist "%DOWNLOAD_DIR%\%%B" (
      set "DUP_FOUND=1"
      set "DUP_LOCAL=%%B"
      set "DUP_SHA=%%A"
      exit /b 0
    )
  )
)
exit /b 1

:compute_sha256
set "FILE_HASH="
if not exist "%~1" exit /b 1
for /f "tokens=* delims=" %%H in ('certutil.exe -hashfile "%~1" SHA256 ^| findstr /v /i /c:"hash of file" /c:"CertUtil"') do (
  if not defined FILE_HASH set "FILE_HASH=%%H"
)
set "FILE_HASH=!FILE_HASH: =!"
if not defined FILE_HASH exit /b 1
exit /b 0

:choose_local_name
set "CONTENT_ALREADY_LOCAL=0"
set "LOCAL_NAME=%~1"
if not exist "%DOWNLOAD_DIR%\!LOCAL_NAME!" exit /b 0

set "EXISTING_HASH="
call :compute_sha256 "%DOWNLOAD_DIR%\!LOCAL_NAME!"
set "EXISTING_HASH=!FILE_HASH!"
set "FILE_HASH=%~2"
if /i "!EXISTING_HASH!"=="!FILE_HASH!" (
  set "CONTENT_ALREADY_LOCAL=1"
  exit /b 0
)

for %%F in ("%~1") do (
  set "NAME_BASE=%%~nF"
  set "NAME_EXT=%%~xF"
)
set "HASH_SHORT=!FILE_HASH:~0,12!"
set "LOCAL_NAME=!NAME_BASE!__!HASH_SHORT!!NAME_EXT!"
if exist "%DOWNLOAD_DIR%\!LOCAL_NAME!" (
  set "EXISTING_HASH="
  call :compute_sha256 "%DOWNLOAD_DIR%\!LOCAL_NAME!"
  set "EXISTING_HASH=!FILE_HASH!"
  set "FILE_HASH=%~2"
  if /i "!EXISTING_HASH!"=="!FILE_HASH!" set "CONTENT_ALREADY_LOCAL=1"
)
exit /b 0

:write_catalogue_current
set "CAT_WRITE_STATUS=%~1"
if not defined FILE_HASH set "FILE_HASH=-"
if not defined LOCAL_NAME set "LOCAL_NAME=-"
if not defined REMOTE_ETAG set "REMOTE_ETAG=-"
if not defined REMOTE_LENGTH set "REMOTE_LENGTH=-"

set "CAT_RECORD_FOUND=0"
> "%CATALOGUE_TMP%" (
  if exist "%CATALOGUE%" (
    for /f "usebackq tokens=1-15 delims=|" %%A in ("%CATALOGUE%") do (
      set "R1=%%A"
      set "R2=%%B"
      set "R3=%%C"
      set "R4=%%D"
      set "R5=%%E"
      set "R6=%%F"
      set "R7=%%G"
      set "R8=%%H"
      set "R9=%%I"
      set "R10=%%J"
      set "R11=%%K"
      set "R12=%%L"
      set "R13=%%M"
      set "R14=%%N"
      set "R15=%%O"
      set "ROW_MATCH=0"

      if /i "!R1!"=="!DOC_URL!" (
        if not "!FILE_HASH!"=="-" if /i "!R10!"=="!FILE_HASH!" set "ROW_MATCH=1"
        if /i "!R6!"=="!PDF_URL!" (
          if "!FILE_HASH!"=="-" set "ROW_MATCH=1"
          if "!R10!"=="-" set "ROW_MATCH=1"
        )

        if "!ROW_MATCH!"=="1" (
          set "WRITE_HASH=!FILE_HASH!"
          set "WRITE_LOCAL=!LOCAL_NAME!"
          set "WRITE_STATUS=!CAT_WRITE_STATUS!"
          if "!WRITE_HASH!"=="-" set "WRITE_HASH=!R10!"
          if "!WRITE_LOCAL!"=="-" set "WRITE_LOCAL=!R13!"
          if /i "!R14!"=="CURRENT" if /i "!CAT_WRITE_STATUS!"=="AVAILABLE" set "WRITE_STATUS=CURRENT"
          echo(!DOC_URL!^|!PRODUCT_ID!^|!DOC_FAMILY!^|!SOURCE_VERSION!^|!DOC_VERSION!^|!PDF_URL!^|!PDF_NAME!^|!REMOTE_ETAG!^|!REMOTE_LENGTH!^|!WRITE_HASH!^|!R11!^|!RUN_SEEN!^|!WRITE_LOCAL!^|!WRITE_STATUS!^|!TARGET_URL!
          set "CAT_RECORD_FOUND=1"
        ) else (
          if /i "!R14!"=="CURRENT" set "R14=HISTORICAL"
          if /i "!R14!"=="AVAILABLE" set "R14=HISTORICAL"
          echo(!R1!^|!R2!^|!R3!^|!R4!^|!R5!^|!R6!^|!R7!^|!R8!^|!R9!^|!R10!^|!R11!^|!R12!^|!R13!^|!R14!^|!R15!
        )
      ) else (
        echo(!R1!^|!R2!^|!R3!^|!R4!^|!R5!^|!R6!^|!R7!^|!R8!^|!R9!^|!R10!^|!R11!^|!R12!^|!R13!^|!R14!^|!R15!
      )
    )
  )

  if "!CAT_RECORD_FOUND!"=="0" (
    echo(!DOC_URL!^|!PRODUCT_ID!^|!DOC_FAMILY!^|!SOURCE_VERSION!^|!DOC_VERSION!^|!PDF_URL!^|!PDF_NAME!^|!REMOTE_ETAG!^|!REMOTE_LENGTH!^|!FILE_HASH!^|!RUN_SEEN!^|!RUN_SEEN!^|!LOCAL_NAME!^|!CAT_WRITE_STATUS!^|!TARGET_URL!
  )
)
move /y "%CATALOGUE_TMP%" "%CATALOGUE%" >nul
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
echo [INFO] Running parser, tracking, version, and catalogue self-tests under cmd.exe...

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
echo [PASS] Product/document parser

call :parse_doc_identity "/document/forticamera/latest/release-notes" "FortiCamera-v2.2.3-Release_Notes.pdf"
if /i not "!PRODUCT_ID!"=="forticamera" (
  echo [FAIL] Product identity parser failed.
  exit /b 16
)
if /i not "!SOURCE_VERSION!"=="latest" (
  echo [FAIL] Source version parser failed.
  exit /b 17
)
if /i not "!DOC_VERSION!"=="2.2.3" (
  echo [FAIL] Filename version inference failed: !DOC_VERSION!.
  exit /b 18
)
echo [PASS] Product/family/version parser

set "ORIGINAL_MANIFEST=%MANIFEST%"
set "ORIGINAL_CATALOGUE=%CATALOGUE%"
set "ORIGINAL_DOWNLOAD_DIR=%DOWNLOAD_DIR%"
set "ORIGINAL_TARGET_URL=%TARGET_URL%"
set "ORIGINAL_RUN_SEEN=%RUN_SEEN%"

set "MANIFEST=%TEMP_DIR%\selftest-downloads.db"
set "CATALOGUE=%TEMP_DIR%\selftest-catalogue.db"
set "DOWNLOAD_DIR=%TEMP_DIR%\selftest-downloads"
set "TARGET_URL=https://docs.fortinet.com/product/example/1.0"
set "RUN_SEEN=SELFTEST-1"
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"
> "%MANIFEST%" type nul
> "%CATALOGUE%" type nul
> "%DOWNLOAD_DIR%\sample.pdf" echo test

call :write_manifest "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-one" "sample.pdf"
if errorlevel 1 (
  echo [FAIL] Tracking manifest write failed.
  exit /b 19
)
call :classify_download "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-one"
if /i not "!TRACK_STATUS!"=="UNCHANGED" (
  echo [FAIL] Tracking expected UNCHANGED, got !TRACK_STATUS!.
  exit /b 20
)
call :classify_download "https://docs.fortinet.com/document/example/1.0/sample" "https://example.test/sample.pdf" "sample.pdf" "etag-two"
if /i not "!TRACK_STATUS!"=="CHANGED" (
  echo [FAIL] Tracking expected CHANGED, got !TRACK_STATUS!.
  exit /b 21
)
echo [PASS] Download tracking classifications

set "DOC_URL=https://docs.fortinet.com/document/example/1.0/sample"
set "PRODUCT_ID=example"
set "DOC_FAMILY=sample"
set "SOURCE_VERSION=1.0"
set "DOC_VERSION=1.0"
set "PDF_URL=https://example.test/sample.pdf"
set "PDF_NAME=sample.pdf"
set "REMOTE_ETAG=etag-one"
set "REMOTE_LENGTH=5"
call :compute_sha256 "%DOWNLOAD_DIR%\sample.pdf"
set "LOCAL_NAME=sample.pdf"
call :write_catalogue_current "CURRENT"
if errorlevel 1 (
  echo [FAIL] Catalogue write failed.
  exit /b 22
)

call :family_version_seen "example" "sample" "1.0"
if errorlevel 1 (
  echo [FAIL] Catalogue version lookup failed.
  exit /b 23
)

call :lookup_duplicate_hash "!FILE_HASH!"
if errorlevel 1 (
  echo [FAIL] Catalogue SHA-256 duplicate lookup failed.
  exit /b 24
)

set "RUN_SEEN=SELFTEST-2"
set "REMOTE_ETAG=etag-two"
set "FILE_HASH=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
set "LOCAL_NAME=sample-v2.pdf"
> "%DOWNLOAD_DIR%\sample-v2.pdf" echo changed
call :write_catalogue_current "CURRENT"
if errorlevel 1 (
  echo [FAIL] Catalogue historical revision write failed.
  exit /b 25
)
findstr /c:"|HISTORICAL|" "%CATALOGUE%" >nul
if errorlevel 1 (
  echo [FAIL] Catalogue did not preserve historical revision.
  exit /b 26
)

echo [PASS] Version catalogue and historical revision retention

set "MANIFEST=%ORIGINAL_MANIFEST%"
set "CATALOGUE=%ORIGINAL_CATALOGUE%"
set "DOWNLOAD_DIR=%ORIGINAL_DOWNLOAD_DIR%"
set "TARGET_URL=%ORIGINAL_TARGET_URL%"
set "RUN_SEEN=%ORIGINAL_RUN_SEEN%"
del /q "%TEMP_DIR%\selftest-downloads.db" >nul 2>&1
del /q "%TEMP_DIR%\selftest-catalogue.db" >nul 2>&1
rmdir /s /q "%TEMP_DIR%\selftest-downloads" >nul 2>&1

echo [PASS] cmd.exe parser, tracking, and catalogue self-test
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

where certutil.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] certutil.exe
  set "DOCTOR_FAIL=1"
) else echo [PASS] certutil.exe

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

if not exist "%MANIFEST%" type nul > "%MANIFEST%" 2>nul
if not exist "%CATALOGUE%" type nul > "%CATALOGUE%" 2>nul

if not exist "%MANIFEST%" (
  echo [FAIL] tracking database
  set "DOCTOR_FAIL=1"
) else echo [PASS] tracking database

if not exist "%CATALOGUE%" (
  echo [FAIL] version catalogue
  set "DOCTOR_FAIL=1"
) else echo [PASS] version catalogue

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
echo(#####       #####   ## Discover, version and synchronize docs         ##
echo(                    ## directly from docs.fortinet.com                ##
echo(##### ##### #####   ## Windows native: cmd + curl + certutil          ##
echo( #### ##### ####    ## v%APP_VERSION%                                         ##
echo(  ### ##### ###     ###################################################
exit /b 0
