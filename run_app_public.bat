@echo off
REM ============================================================
REM  Launch SpeedRunner AND create a FREE public link to share.
REM  It uses a Cloudflare tunnel, which gives a public address like
REM    https://something.trycloudflare.com
REM  The link works while THIS window stays open and your laptop is on.
REM  Close the window (or shut the laptop) and the link goes down.
REM ============================================================
cd /d "%~dp0"

set "PY="
if exist "%~dp0python\python.exe" set "PY=%~dp0python\python.exe"
if not defined PY ( where py     >nul 2>&1 && set "PY=py" )
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY (
  echo Python was not found. Please run install-windows.bat first.
  start "" "https://www.python.org/downloads/"
  pause
  exit /b 1
)

%PY% -m pip install -q -r requirements.txt
echo Checking for updates...
%PY% -m scanner.update

REM Download the tunnel tool once.
if not exist "%~dp0cloudflared.exe" (
  echo Downloading the tunnel tool ^(one time^)...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile (Join-Path '%~dp0' 'cloudflared.exe')"
  if errorlevel 1 ( echo Download failed - check the internet connection. & pause & exit /b 1 )
)

REM Start the app in its own window (listens on localhost:5000).
start "SpeedRunner server" "%PY%" -m scanner.app

echo.
echo  ============================================================
echo   Your PUBLIC LINK is starting. In a moment you'll see a line
echo   with a web address ending in  .trycloudflare.com
echo.
echo   Share THAT link (plus an invite code) with people.
echo   Keep this window OPEN - closing it takes the link down.
echo  ============================================================
echo.
"%~dp0cloudflared.exe" tunnel --url http://localhost:5000
pause
