@echo off
rem v0.0.12 CRLF ZIP-distribution marker
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ACTION=%~1"
set "CATEGORY_URL=%~2"
set "LIMIT=%~3"
if not defined LIMIT set "LIMIT=0"

set "RUNTIME=%~dp0runtime"
set "TEMP_DIR=%RUNTIME%\temp"
set "STATE_DIR=%RUNTIME%\state"
set "KB_DIR=%RUNTIME%\kb"
set "KB_ARTICLES=%KB_DIR%\articles"
set "KB_DB=%STATE_DIR%\kb.db"
set "KB_HISTORY=%STATE_DIR%\kb-history.db"
set "KB_TMP=%TEMP_DIR%\kb-db.tmp"
set "ROOT_HTML=%TEMP_DIR%\kb-root.html"
set "INDEX_XML=%TEMP_DIR%\kb-sitemap-index.xml"
set "SITEMAP_LIST=%TEMP_DIR%\kb-sitemaps.txt"
set "ARTICLE_LIST=%TEMP_DIR%\kb-articles.txt"
set "SITEMAP_XML=%TEMP_DIR%\kb-topics.xml"
set "SITEMAP_PARSED=%TEMP_DIR%\kb-topics-parsed.txt"
set "ARTICLE_TMP=%TEMP_DIR%\kb-article.tmp"
set "PARSER=%~dp0scripts\fortinet-parser.js"
set "COMMUNITY=https://community.fortinet.com"

if /i "%ACTION%"=="categories" goto :categories
if /i "%ACTION%"=="inventory" goto :category
if /i "%ACTION%"=="check" goto :category
if /i "%ACTION%"=="sync" goto :category

echo Usage:
echo   run.bat kb categories
echo   run.bat kb inventory https://community.fortinet.com/fortigate-3 [limit]
echo   run.bat kb check     https://community.fortinet.com/fortigate-3 [limit]
echo   run.bat kb sync      https://community.fortinet.com/fortigate-3 [limit]
exit /b 2

:doctor
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" >nul 2>&1
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
if not exist "%KB_DIR%" mkdir "%KB_DIR%" >nul 2>&1
if not exist "%KB_ARTICLES%" mkdir "%KB_ARTICLES%" >nul 2>&1
if not exist "%KB_DB%" type nul > "%KB_DB%"
if not exist "%KB_HISTORY%" type nul > "%KB_HISTORY%"
where curl.exe >nul 2>&1 || exit /b 1
where certutil.exe >nul 2>&1 || exit /b 1
where cscript.exe >nul 2>&1 || (
  echo [FAIL] cscript.exe is required for Knowledge Base sitemap parsing.
  exit /b 1
)
if not exist "%PARSER%" (
  echo [FAIL] Missing scripts\fortinet-parser.js.
  exit /b 1
)
exit /b 0

:categories
call :doctor
if errorlevel 1 exit /b 1
echo [INFO] Fetching Fortinet Knowledge Base categories...
curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "%COMMUNITY%/knowledge-base" -o "%ROOT_HTML%"
if errorlevel 1 (
  echo [FAIL] Could not retrieve the Fortinet Knowledge Base.
  exit /b 3
)
cscript.exe //nologo "%PARSER%" kb-categories "%ROOT_HTML%" "%SITEMAP_PARSED%"
if errorlevel 1 (
  echo [FAIL] Could not discover Knowledge Base categories.
  exit /b 4
)
echo.
echo Fortinet Knowledge Base categories:
echo.
for /f "usebackq tokens=1,* delims=|" %%A in ("%SITEMAP_PARSED%") do echo   %%A  -  %%B
exit /b 0

:category
call :doctor
if errorlevel 1 exit /b 1
if not defined CATEGORY_URL (
  echo [FAIL] No Knowledge Base category URL supplied.
  exit /b 2
)
if /i not "%CATEGORY_URL:~0,31%"=="https://community.fortinet.com/" (
  echo [FAIL] Category URL must begin with https://community.fortinet.com/
  exit /b 2
)

set "CATEGORY_PATH=%CATEGORY_URL:https://community.fortinet.com=%"
if "%CATEGORY_PATH%"=="" (
  echo [FAIL] Supply a specific Knowledge Base category URL.
  exit /b 2
)
if "%CATEGORY_PATH:~0,1%"=="/" set "CATEGORY_PATH=%CATEGORY_PATH:~1%"
for /f "tokens=1 delims=/?#" %%A in ("%CATEGORY_PATH%") do set "CATEGORY_SLUG=%%A"
set "CATEGORY_FILTER=/%CATEGORY_SLUG%/"
set "CATEGORY_DIR=%KB_ARTICLES%\%CATEGORY_SLUG%"
if not exist "%CATEGORY_DIR%" mkdir "%CATEGORY_DIR%" >nul 2>&1

echo [INFO] Discovering Knowledge Base article URLs from Fortinet topic sitemaps...
curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 120 "%COMMUNITY%/sitemap.xml" -o "%INDEX_XML%"
if errorlevel 1 (
  echo [FAIL] Could not retrieve Community sitemap index.
  exit /b 3
)
cscript.exe //nologo "%PARSER%" sitemap-index "%INDEX_XML%" "%SITEMAP_LIST%"
if errorlevel 1 (
  echo [FAIL] Could not discover Community topic sitemaps.
  exit /b 4
)

> "%ARTICLE_LIST%" type nul
set /a SITEMAP_COUNT=0
for /f "usebackq delims=" %%S in ("%SITEMAP_LIST%") do (
  set /a SITEMAP_COUNT+=1
  echo [INFO] Reading sitemap !SITEMAP_COUNT!: %%S
  curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 180 "%%S" -o "%SITEMAP_XML%"
  if errorlevel 1 (
    echo [FAIL] Could not retrieve topic sitemap.
    exit /b 5
  )
  cscript.exe //nologo "%PARSER%" sitemap "%SITEMAP_XML%" "%SITEMAP_PARSED%" "%CATEGORY_FILTER%"
  if not errorlevel 1 type "%SITEMAP_PARSED%" >> "%ARTICLE_LIST%"
)

for %%F in ("%ARTICLE_LIST%") do if %%~zF LEQ 0 (
  echo [FAIL] No Knowledge Base articles were discovered for %CATEGORY_SLUG%.
  exit /b 6
)

set "RUN_SEEN=%DATE%T%TIME%"
set /a TOTAL=0
set /a NEW_COUNT=0
set /a CHANGED_COUNT=0
set /a UNCHANGED_COUNT=0
set /a MISSING_COUNT=0
set /a DOWNLOADED_COUNT=0
set /a SAME_CONTENT_COUNT=0
set /a FAILED=0

for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%ARTICLE_LIST%") do (
  if !LIMIT! EQU 0 (
    call :process_article "%%A" "%%B" "%%C"
  ) else if !TOTAL! LSS !LIMIT! (
    call :process_article "%%A" "%%B" "%%C"
  )
)

echo.
echo ------------------------------------------------------------
echo KB category             : %CATEGORY_SLUG%
echo Articles discovered     : !TOTAL!
echo New articles            : !NEW_COUNT!
echo Changed articles        : !CHANGED_COUNT!
echo Unchanged articles      : !UNCHANGED_COUNT!
echo Missing local articles  : !MISSING_COUNT!
if /i "%ACTION%"=="sync" echo Downloaded/updated      : !DOWNLOADED_COUNT!
if /i "%ACTION%"=="sync" echo Metadata-only changes   : !SAME_CONTENT_COUNT!
echo Warnings/failures       : !FAILED!
echo KB corpus directory     : %CATEGORY_DIR%
echo KB tracking database    : %KB_DB%
echo ------------------------------------------------------------

if !FAILED! GTR 0 exit /b 7
exit /b 0

:process_article
set /a TOTAL+=1
set "ARTICLE_URL=%~1"
set "ARTICLE_LASTMOD=%~2"
set "ARTICLE_ID=%~3"
if "!ARTICLE_ID!"=="-" set "ARTICLE_ID=!TOTAL!"
set "LOCAL_NAME=article-!ARTICLE_ID!.html"
set "LOCAL_REL=runtime\kb\articles\%CATEGORY_SLUG%\!LOCAL_NAME!"
set "LOCAL_FILE=%~dp0!LOCAL_REL!"

call :lookup_kb "!ARTICLE_URL!"
if errorlevel 1 (
  set "ARTICLE_STATUS=NEW"
  set /a NEW_COUNT+=1
) else (
  set "ARTICLE_STATUS=UNCHANGED"
  if not "!PREV_LASTMOD!"=="-" if not "!ARTICLE_LASTMOD!"=="-" if /i not "!PREV_LASTMOD!"=="!ARTICLE_LASTMOD!" set "ARTICLE_STATUS=CHANGED"
  if not exist "!PREV_LOCAL!" set "ARTICLE_STATUS=MISSING_LOCAL"
  if /i "!ARTICLE_STATUS!"=="CHANGED" set /a CHANGED_COUNT+=1
  if /i "!ARTICLE_STATUS!"=="MISSING_LOCAL" set /a MISSING_COUNT+=1
  if /i "!ARTICLE_STATUS!"=="UNCHANGED" set /a UNCHANGED_COUNT+=1
)

if /i "%ACTION%"=="inventory" (
  echo [!ARTICLE_STATUS!] !ARTICLE_URL!
  exit /b 0
)
if /i "%ACTION%"=="check" (
  if /i not "!ARTICLE_STATUS!"=="UNCHANGED" echo [!ARTICLE_STATUS!] !ARTICLE_URL!
  exit /b 0
)

if /i "!ARTICLE_STATUS!"=="UNCHANGED" exit /b 0

echo [!ARTICLE_STATUS!] !ARTICLE_URL!
curl.exe -L --fail --silent --show-error --connect-timeout 20 --max-time 180 "!ARTICLE_URL!" -o "%ARTICLE_TMP%"
if errorlevel 1 (
  echo [WARN] Failed to retrieve KB article.
  set /a FAILED+=1
  exit /b 0
)
for %%Z in ("%ARTICLE_TMP%") do if %%~zZ LEQ 0 (
  echo [WARN] Retrieved KB article is empty.
  set /a FAILED+=1
  exit /b 0
)

call :compute_sha256 "%ARTICLE_TMP%"
if errorlevel 1 (
  echo [WARN] Could not hash KB article.
  set /a FAILED+=1
  exit /b 0
)
set "NEW_HASH=!FILE_HASH!"

if defined PREV_SHA if not "!PREV_SHA!"=="-" if /i "!PREV_SHA!"=="!NEW_HASH!" (
  del /q "%ARTICLE_TMP%" >nul 2>&1
  call :write_kb "!ARTICLE_URL!" "!ARTICLE_LASTMOD!" "!PREV_SHA!" "!PREV_FIRST!" "!PREV_LOCAL!" "CURRENT"
  set /a SAME_CONTENT_COUNT+=1
  echo [INFO] Sitemap metadata changed but article bytes did not.
  exit /b 0
)

if defined PREV_SHA if not "!PREV_SHA!"=="-" if exist "!PREV_LOCAL!" (
  set "OLD_SHORT=!PREV_SHA:~0,12!"
  set "HIST_REL=runtime\kb\articles\%CATEGORY_SLUG%\article-!ARTICLE_ID!__!OLD_SHORT!.html"
  set "HIST_FILE=%~dp0!HIST_REL!"
  if not exist "!HIST_FILE!" copy /y "!PREV_LOCAL!" "!HIST_FILE!" >nul
  >> "%KB_HISTORY%" echo(!ARTICLE_URL!^|%CATEGORY_SLUG%^|!PREV_LASTMOD!^|!PREV_SHA!^|!PREV_FIRST!^|!RUN_SEEN!^|!HIST_REL!^|HISTORICAL
)

move /y "%ARTICLE_TMP%" "!LOCAL_FILE!" >nul
if errorlevel 1 (
  echo [WARN] Could not store KB article.
  set /a FAILED+=1
  exit /b 0
)

set "FIRST_SEEN=!RUN_SEEN!"
if defined PREV_FIRST set "FIRST_SEEN=!PREV_FIRST!"
call :write_kb "!ARTICLE_URL!" "!ARTICLE_LASTMOD!" "!NEW_HASH!" "!FIRST_SEEN!" "!LOCAL_REL!" "CURRENT"
if errorlevel 1 (
  echo [WARN] KB article saved but tracking update failed.
  set /a FAILED+=1
  exit /b 0
)
set /a DOWNLOADED_COUNT+=1
echo [OK] Saved !LOCAL_NAME!
exit /b 0

:lookup_kb
set "PREV_LASTMOD="
set "PREV_SHA="
set "PREV_FIRST="
set "PREV_LOCAL="
if not exist "%KB_DB%" exit /b 1
for /f "usebackq tokens=1-8 delims=|" %%A in ("%KB_DB%") do (
  if /i "%%A"=="%~1" (
    set "PREV_LASTMOD=%%C"
    set "PREV_SHA=%%D"
    set "PREV_FIRST=%%E"
    set "PREV_LOCAL=%%G"
    exit /b 0
  )
)
exit /b 1

:write_kb
> "%KB_TMP%" (
  if exist "%KB_DB%" for /f "usebackq tokens=1,* delims=|" %%A in ("%KB_DB%") do if /i not "%%A"=="%~1" echo(%%A^|%%B
  echo(%~1^|%CATEGORY_SLUG%^|%~2^|%~3^|%~4^|!RUN_SEEN!^|%~5^|%~6
)
move /y "%KB_TMP%" "%KB_DB%" >nul
exit /b %errorlevel%

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
