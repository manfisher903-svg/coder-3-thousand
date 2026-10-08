@echo off
REM Double-click to launch SpeedRunner (Windows) - opens in your browser.
REM It auto-updates to the latest version first (your accounts and scans are kept).
cd /d "%~dp0"

set "PY="
where py     >nul 2>&1 && set "PY=py"
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY (
  echo Python is not installed. Opening the download page...
  echo After installing ^(tick "Add python.exe to PATH"^), run this again.
  start "" "https://www.python.org/downloads/"
  pause
  exit /b 1
)

%PY% -m pip install -q -r requirements.txt
echo Checking for updates...
%PY% -m scanner.update
%PY% -m scanner.app
pause
