@echo off
REM Launch SpeedRunner so your PHONE can open it over Wi-Fi.
REM Watch this window - it prints the http://...:5000 address to type on your phone.
cd /d "%~dp0"

REM Prefer the private Python installed next to the app; fall back to a system one.
set "PY="
if exist "%~dp0python\python.exe" set "PY=%~dp0python\python.exe"
if not defined PY ( where py     >nul 2>&1 && set "PY=py" )
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY (
  echo Python was not found. Please run install-windows.bat again.
  start "" "https://www.python.org/downloads/"
  pause
  exit /b 1
)

"%PY%" -m pip install -q -r requirements.txt
"%PY%" -m scanner.update
set PIS_LAN=1
"%PY%" -m scanner.app
pause
