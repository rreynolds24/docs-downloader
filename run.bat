@echo off
setlocal
cd /d "%~dp0"

if not exist "docs-downloader.bat" (
  echo [FAIL] docs-downloader.bat is missing.
  exit /b 1
)

call "%~dp0docs-downloader.bat" %*
exit /b %errorlevel%
