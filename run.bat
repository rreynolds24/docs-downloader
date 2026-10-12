@echo off
setlocal
cd /d "%~dp0"

if /i "%~1"=="update" (
  if not exist "%~dp0update.bat" (
    echo [FAIL] update.bat is missing.
    exit /b 1
  )
  call "%~dp0update.bat"
  exit /b %errorlevel%
)

if /i "%~1"=="hubs" (
  if not exist "%~dp0solution-downloader.bat" (
    echo [FAIL] solution-downloader.bat is missing.
    exit /b 1
  )
  call "%~dp0solution-downloader.bat" hubs
  exit /b %errorlevel%
)

if /i "%~1"=="kb" (
  if not exist "%~dp0kb-downloader.bat" (
    echo [FAIL] kb-downloader.bat is missing.
    exit /b 1
  )
  call "%~dp0kb-downloader.bat" %2 %3 %4
  exit /b %errorlevel%
)

if not exist "docs-downloader.bat" (
  echo [FAIL] docs-downloader.bat is missing.
  exit /b 1
)

call "%~dp0docs-downloader.bat" %*
exit /b %errorlevel%
