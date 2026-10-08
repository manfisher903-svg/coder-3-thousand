@echo off
REM Launch SpeedRunner so your PHONE can open it over Wi-Fi.
REM Watch this window - it prints the http://...:5000 address to type on your phone.
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
%PY% -m scanner.update
set PIS_LAN=1
%PY% -m scanner.app
pause
