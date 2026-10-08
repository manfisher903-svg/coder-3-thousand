@echo off
REM Double-click to launch SpeedRunner (Windows) - opens in your browser.
REM It auto-updates to the latest version first (your accounts and scans are kept).
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
echo Checking for updates...
"%PY%" -m scanner.update
"%PY%" -m scanner.app
pause
