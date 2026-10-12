@echo off
rem v0.0.11 release-integrity marker: deterministic updater bootstrap
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "MODE=%~1"
set "TARGET_URL=%~2"
set "BASE_URL=https://docs.fortinet.com"
set "RUNTIME=%~dp0runtime"
set "TEMP_DIR=%RUNTIME%\temp"
set "DOWNLOAD_DIR=%RUNTIME%\downloads"
set "STATE_DIR=%RUNTIME%\state"
set "MANIFEST=%STATE_DIR%\downloads.db"
set "CATALOGUE=%STATE_DIR%\catalogue.db"
set "SOURCES=%STATE_DIR%\sources.db"
set "MANIFEST_TMP=%TEMP_DIR%\solution-downloads.tmp"
set "CATALOGUE_TMP=%TEMP_DIR%\solution-catalogue.tmp"
set "SOURCES_TMP=%TEMP_DIR%\sources.tmp"
set "PAGE_HTML=%TEMP_DIR%\solution.html"
set "DOC_HTML=%TEMP_DIR%\solution-document.html"
set "RESOURCE_LIST=%TEMP_DIR%\solution-resources.txt"
set "PDF_OUT=%TEMP_DIR%\solution-reader-pdf.txt"
set "HEADER_FILE=%TEMP_DIR%\solution-headers.txt"
set "DOWNLOAD_TMP=%TEMP_DIR%\solution-download.tmp"
set "PARSER=%~dp0scripts\fortinet-parser.js"

if /i "%MODE%"=="hubs" goto :hubs
if /i not "%MODE%"=="inventory" if /i not "%MODE%"=="check" if /i not "%MODE%"=="download" (
  echo [FAIL] Solution module mode must be inventory, check, download, or hubs.
  exit /b 2
)
if not defined TARGET_URL (
  echo [FAIL] No Solution Hub URL supplied.
  exit /b 2
)
if /i not "%TARGET_URL:~0,26%"=="https://docs.fortinet.com/" (
  echo [FAIL] Solution Hub URL must be on https://docs.fortinet.com/
  exit /b 2
)

call :doctor
if errorlevel 1 exit /b 1

set "RUN_SEEN=%DATE%T%TIME%"

echo [INFO] Fetching Solution Hub page...
curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "%TARGET_URL%" -o "%PAGE_HTML%"
if errorlevel 1 (
  echo [FAIL] Could not retrieve Solution Hub page.
  exit /b 3
)

cscript.exe //nologo "%PARSER%" solution "%PAGE_HTML%" "%RESOURCE_LIST%"
if errorlevel 1 (
  echo [FAIL] No supported Fortinet resources were discovered on the Solution Hub page.
  exit /b 4
)

set /a TOTAL=0
set /a RESOLVED=0
set /a NO_PDF=0
set /a EXISTING=0
set /a NEW_RESOURCE=0
set /a DOWNLOADED=0
set /a DEDUPED=0
set /a FAILED=0

for /f "usebackq tokens=1,* delims=|" %%A in ("%RESOURCE_LIST%") do (
  set /a TOTAL+=1
  set "RESOURCE_TYPE=%%A"
  set "RESOURCE_URL=%%B"
  set "PDF_URL="
  set "PDF_NAME="
  set "FILE_HASH=-"
  set "LOCAL_NAME=-"

  echo.
  echo [INFO] !TOTAL!: !RESOURCE_URL!

  if /i "!RESOURCE_TYPE!"=="DOC" (
    curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "!RESOURCE_URL!" -o "%DOC_HTML%"
    if errorlevel 1 (
      echo [WARN] Could not retrieve curated document page.
      set /a FAILED+=1
    ) else (
      cscript.exe //nologo "%PARSER%" readerpdf "%DOC_HTML%" "%PDF_OUT%" >nul 2>&1
      if errorlevel 1 (
        echo [INFO] Curated document has no PDF target; skipping.
        set /a NO_PDF+=1
      ) else (
        set /p PDF_URL=<"%PDF_OUT%"
      )
    )
  ) else if /i "!RESOURCE_TYPE!"=="PDF" (
    set "PDF_URL=!RESOURCE_URL!"
  )

  if defined PDF_URL (
    set /a RESOLVED+=1
    for %%F in ("!PDF_URL:/=\!") do set "PDF_NAME=%%~nxF"
    call :get_remote_metadata "!PDF_URL!"
    call :lookup_duplicate_remote "!PDF_URL!" "!REMOTE_ETAG!" "!REMOTE_LENGTH!"

    if "!DUP_FOUND!"=="1" (
      set /a EXISTING+=1
      set /a DEDUPED+=1
      set "FILE_HASH=!DUP_SHA!"
      set "LOCAL_NAME=!DUP_LOCAL!"
      echo [DUPLICATE_CONTENT] Already stored as !LOCAL_NAME!
      call :write_manifest "!RESOURCE_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!" "!LOCAL_NAME!"
      call :write_source "!RESOURCE_URL!" "!PDF_URL!" "!FILE_HASH!" "!LOCAL_NAME!"
    ) else (
      set /a NEW_RESOURCE+=1
      echo [NEW_RESOURCE] !PDF_NAME!

      if /i "!MODE!"=="download" (
        if exist "%DOWNLOAD_TMP%" del /q "%DOWNLOAD_TMP%" >nul 2>&1
        curl.exe -L --fail --show-error --progress-bar --connect-timeout 20 --max-time 1800 "!PDF_URL!" -o "%DOWNLOAD_TMP%"
        if errorlevel 1 (
          echo [WARN] Download failed.
          set /a FAILED+=1
        ) else (
          for %%Z in ("%DOWNLOAD_TMP%") do (
            if %%~zZ LEQ 0 (
              echo [WARN] Downloaded file is empty.
              set /a FAILED+=1
            ) else (
              call :compute_sha256 "%DOWNLOAD_TMP%"
              if errorlevel 1 (
                echo [WARN] Could not compute SHA-256.
                set /a FAILED+=1
              ) else (
                call :lookup_duplicate_hash "!FILE_HASH!"
                if "!DUP_FOUND!"=="1" (
                  set "LOCAL_NAME=!DUP_LOCAL!"
                  del /q "%DOWNLOAD_TMP%" >nul 2>&1
                  set /a DEDUPED+=1
                  echo [DUPLICATE_CONTENT] SHA-256 matches !LOCAL_NAME!
                ) else (
                  call :choose_local_name "!PDF_NAME!" "!FILE_HASH!"
                  if "!CONTENT_ALREADY_LOCAL!"=="1" (
                    del /q "%DOWNLOAD_TMP%" >nul 2>&1
                    set /a DEDUPED+=1
                  ) else (
                    move /y "%DOWNLOAD_TMP%" "%DOWNLOAD_DIR%\!LOCAL_NAME!" >nul
                    if errorlevel 1 (
                      echo [WARN] Could not store downloaded PDF.
                      set /a FAILED+=1
                    ) else (
                      set /a DOWNLOADED+=1
                      echo [OK] Saved: %DOWNLOAD_DIR%\!LOCAL_NAME!
                    )
                  )
                )

                if not "!LOCAL_NAME!"=="-" (
                  call :write_manifest "!RESOURCE_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!" "!LOCAL_NAME!"
                  call :write_catalogue "!RESOURCE_URL!" "!PDF_URL!" "!PDF_NAME!" "!REMOTE_ETAG!" "!REMOTE_LENGTH!" "!FILE_HASH!" "!LOCAL_NAME!" "CURRENT"
                  call :write_source "!RESOURCE_URL!" "!PDF_URL!" "!FILE_HASH!" "!LOCAL_NAME!"
                )
              )
            )
          )
        )
      ) else (
        call :write_source "!RESOURCE_URL!" "!PDF_URL!" "-" "-"
      )
    )
  )
)

echo.
echo ------------------------------------------------------------
echo Solution page          : %TARGET_URL%
echo Resources discovered   : !TOTAL!
echo PDF targets resolved   : !RESOLVED!
echo No PDF available       : !NO_PDF!
echo Existing/de-duplicated : !EXISTING!
echo New resources          : !NEW_RESOURCE!
if /i "!MODE!"=="download" echo Downloaded             : !DOWNLOADED!
if /i "!MODE!"=="download" echo Duplicate downloads avoided: !DEDUPED!
echo Warnings/failures      : !FAILED!
echo Shared PDF catalogue   : %CATALOGUE%
echo Source provenance      : %SOURCES%
echo ------------------------------------------------------------

if !RESOLVED! EQU 0 exit /b 5
if !FAILED! GTR 0 exit /b 6
exit /b 0

:hubs
call :doctor
if errorlevel 1 exit /b 1
set "TARGET_URL=https://docs.fortinet.com/solution-hubs"
curl.exe -L --fail --silent --show-error "%TARGET_URL%" -o "%PAGE_HTML%"
if errorlevel 1 exit /b 3
cscript.exe //nologo "%PARSER%" hubs "%PAGE_HTML%" "%RESOURCE_LIST%"
if errorlevel 1 (
  echo [FAIL] Could not discover Solution Hub entries.
  exit /b 4
)
echo Fortinet Solution Hubs:
echo.
for /f "usebackq delims=" %%A in ("%RESOURCE_LIST%") do echo   %%A
exit /b 0

:doctor
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" >nul 2>&1
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%" >nul 2>&1
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
if not exist "%MANIFEST%" type nul > "%MANIFEST%"
if not exist "%CATALOGUE%" type nul > "%CATALOGUE%"
if not exist "%SOURCES%" type nul > "%SOURCES%"

where curl.exe >nul 2>&1 || exit /b 1
where certutil.exe >nul 2>&1 || exit /b 1
where cscript.exe >nul 2>&1 || (
  echo [FAIL] cscript.exe is required for Solution Hub parsing.
  exit /b 1
)
if not exist "%PARSER%" (
  echo [FAIL] Missing scripts\fortinet-parser.js.
  exit /b 1
)
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

:lookup_duplicate_remote
set "DUP_FOUND=0"
set "DUP_LOCAL="
set "DUP_SHA=-"
if not exist "%CATALOGUE%" exit /b 1
for /f "usebackq tokens=1-15 delims=|" %%A in ("%CATALOGUE%") do (
  set "ROW_PDF_URL=%%F"
  set "ROW_ETAG=%%H"
  set "ROW_LENGTH=%%I"
  set "ROW_SHA=%%J"
  set "ROW_LOCAL=%%M"
  if not "!ROW_LOCAL!"=="-" if exist "%DOWNLOAD_DIR%\!ROW_LOCAL!" (
    if /i "!ROW_PDF_URL!"=="%~1" (
      set "REMOTE_CONFLICT=0"
      if not "%~2"=="-" if not "!ROW_ETAG!"=="-" if /i not "!ROW_ETAG!"=="%~2" set "REMOTE_CONFLICT=1"
      if not "%~3"=="-" if not "!ROW_LENGTH!"=="-" if /i not "!ROW_LENGTH!"=="%~3" set "REMOTE_CONFLICT=1"
      if "!REMOTE_CONFLICT!"=="0" (
        set "DUP_FOUND=1"
        set "DUP_LOCAL=!ROW_LOCAL!"
        set "DUP_SHA=!ROW_SHA!"
        exit /b 0
      )
    )
    if not "%~2"=="-" if not "%~3"=="-" if /i "!ROW_ETAG!"=="%~2" if /i "!ROW_LENGTH!"=="%~3" (
      set "DUP_FOUND=1"
      set "DUP_LOCAL=!ROW_LOCAL!"
      set "DUP_SHA=!ROW_SHA!"
      exit /b 0
    )
  )
)
exit /b 1

:lookup_duplicate_hash
set "DUP_FOUND=0"
set "DUP_LOCAL="
set "DUP_SHA=-"
for /f "usebackq tokens=10,13 delims=|" %%A in ("%CATALOGUE%") do (
  if /i "%%A"=="%~1" if not "%%B"=="-" if exist "%DOWNLOAD_DIR%\%%B" (
    set "DUP_FOUND=1"
    set "DUP_LOCAL=%%B"
    set "DUP_SHA=%%A"
    exit /b 0
  )
)
exit /b 1

:compute_sha256
set "FILE_HASH="
if not exist "%~1" exit /b 1
for /f "skip=1 tokens=* delims=" %%H in ('certutil.exe -hashfile "%~1" SHA256') do if not defined FILE_HASH set "FILE_HASH=%%H"
set "FILE_HASH=!FILE_HASH: =!"
if "!FILE_HASH:~63,1!"=="" exit /b 1
if not "!FILE_HASH:~64,1!"=="" exit /b 1
set "NON_HEX_HASH="
for /f "delims=0123456789abcdefABCDEF" %%X in ("!FILE_HASH!") do set "NON_HEX_HASH=%%X"
if defined NON_HEX_HASH exit /b 1
exit /b 0

:choose_local_name
set "CONTENT_ALREADY_LOCAL=0"
set "LOCAL_NAME=%~1"
if not exist "%DOWNLOAD_DIR%\!LOCAL_NAME!" exit /b 0
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
set "LOCAL_NAME=!NAME_BASE!__!FILE_HASH:~0,12!!NAME_EXT!"
exit /b 0

:write_manifest
set "WRITE_LOCAL=%~5"
> "%MANIFEST_TMP%" (
  if exist "%MANIFEST%" for /f "usebackq tokens=1,* delims=|" %%A in ("%MANIFEST%") do if /i not "%%A"=="%~1" echo(%%A^|%%B
  echo(%~1^|%~2^|%~3^|%~4^|!WRITE_LOCAL!
)
move /y "%MANIFEST_TMP%" "%MANIFEST%" >nul
exit /b %errorlevel%

:parse_identity
set "PRODUCT_ID=solution"
set "SOURCE_VERSION=unknown"
set "DOC_FAMILY=resource"
set "DOC_VERSION=unknown"
set "URL_PATH=%~1"
if /i "!URL_PATH:~0,35!"=="https://docs.fortinet.com/document/" (
  for /f "tokens=4,5,6 delims=/" %%A in ("!URL_PATH!") do (
    set "PRODUCT_ID=%%A"
    set "SOURCE_VERSION=%%B"
    set "DOC_FAMILY=%%C"
  )
  set "DOC_VERSION=!SOURCE_VERSION!"
) else (
  set "SOLUTION_PATH=%TARGET_URL:https://docs.fortinet.com/=%"
  for /f "tokens=1,2 delims=/" %%A in ("!SOLUTION_PATH!") do (
    set "PRODUCT_ID=solution-%%A"
    set "SOURCE_VERSION=%%B"
  )
  if not defined SOURCE_VERSION set "SOURCE_VERSION=latest"
  set "DOC_VERSION=!SOURCE_VERSION!"
  for %%F in ("%~3") do set "DOC_FAMILY=%%~nF"
)
exit /b 0

:write_catalogue
call :parse_identity "%~1" "%~2" "%~3"
set "CAT_STATUS=%~8"
set "CAT_FOUND=0"
> "%CATALOGUE_TMP%" (
  if exist "%CATALOGUE%" for /f "usebackq tokens=1-15 delims=|" %%A in ("%CATALOGUE%") do (
    set "ROW_MATCH=0"
    if /i "%%A"=="%~1" if /i "%%F"=="%~2" set "ROW_MATCH=1"
    if "!ROW_MATCH!"=="1" (
      echo(%%A^|%%B^|%%C^|%%D^|%%E^|%%F^|%%G^|%~4^|%~5^|%~6^|%%K^|!RUN_SEEN!^|%~7^|!CAT_STATUS!^|%TARGET_URL%
      set "CAT_FOUND=1"
    ) else (
      echo(%%A^|%%B^|%%C^|%%D^|%%E^|%%F^|%%G^|%%H^|%%I^|%%J^|%%K^|%%L^|%%M^|%%N^|%%O
    )
  )
  if "!CAT_FOUND!"=="0" echo(%~1^|!PRODUCT_ID!^|!DOC_FAMILY!^|!SOURCE_VERSION!^|!DOC_VERSION!^|%~2^|%~3^|%~4^|%~5^|%~6^|!RUN_SEEN!^|!RUN_SEEN!^|%~7^|!CAT_STATUS!^|%TARGET_URL%
)
move /y "%CATALOGUE_TMP%" "%CATALOGUE%" >nul
exit /b %errorlevel%

:write_source
set "SRC_FOUND=0"
> "%SOURCES_TMP%" (
  if exist "%SOURCES%" for /f "usebackq tokens=1-7 delims=|" %%A in ("%SOURCES%") do (
    set "ROW_MATCH=0"
    if /i "%%A"=="%TARGET_URL%" if /i "%%B"=="%~1" set "ROW_MATCH=1"
    if "!ROW_MATCH!"=="1" (
      echo(%%A^|%%B^|%~2^|%~3^|%%E^|!RUN_SEEN!^|%~4
      set "SRC_FOUND=1"
    ) else (
      echo(%%A^|%%B^|%%C^|%%D^|%%E^|%%F^|%%G
    )
  )
  if "!SRC_FOUND!"=="0" echo(%TARGET_URL%^|%~1^|%~2^|%~3^|!RUN_SEEN!^|!RUN_SEEN!^|%~4
)
move /y "%SOURCES_TMP%" "%SOURCES%" >nul
exit /b %errorlevel%
