@echo off
REM ============================================================
REM  SpeedRunner - one-click installer for Windows.
REM  Give this ONE file to someone. They double-click it and it:
REM    1) checks for Python (helps them install it if missing),
REM    2) downloads the latest SpeedRunner,
REM    3) puts a SpeedRunner icon on their Desktop,
REM    4) launches it. From then on it auto-updates on every start.
REM ============================================================
setlocal enabledelayedexpansion
title SpeedRunner Installer
cd /d "%~dp0"

REM --- find Python (py launcher preferred, then python) ---
set "PY="
where py     >nul 2>&1 && set "PY=py"
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY (
  echo.
  echo   SpeedRunner needs Python ^(a free, one-time install^).
  echo   I'll open the download page now.
  echo.
  echo   On the FIRST screen of the Python installer, tick the box
  echo        [x] Add python.exe to PATH
  echo   then click Install Now. When it finishes, run this installer again.
  echo.
  start "" "https://www.python.org/downloads/"
  pause
  exit /b 1
)

set "APPDIR=%LOCALAPPDATA%\SpeedRunner"
set "URL=https://github.com/manfisher903-svg/coder-3-thousand/archive/refs/heads/claude/personal-info-scanner-rwixso.zip"

if exist "%APPDIR%\scanner\app.py" (
  echo   SpeedRunner is already installed - launching ^(it will update itself^)...
  goto run
)

echo.
echo   Installing SpeedRunner to:
echo       %APPDIR%
echo   Downloading the latest version...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $z=Join-Path $env:TEMP 'speedrunner.zip'; Invoke-WebRequest -Uri '%URL%' -OutFile $z; $tmp=Join-Path $env:TEMP 'speedrunner_extract'; if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}; Expand-Archive -Path $z -DestinationPath $tmp -Force; $inner=(Get-ChildItem $tmp | Select-Object -First 1).FullName; New-Item -ItemType Directory -Force -Path '%APPDIR%' | Out-Null; Copy-Item (Join-Path $inner '*') '%APPDIR%' -Recurse -Force; Remove-Item $z -Force"
if errorlevel 1 (
  echo.
  echo   Download failed. Check the internet connection and try again.
  pause
  exit /b 1
)

REM --- put a clickable icon on the Desktop for next time ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([IO.Path]::Combine([Environment]::GetFolderPath('Desktop'),'SpeedRunner.lnk')); $s.TargetPath=Join-Path '%APPDIR%' 'run_app.bat'; $s.WorkingDirectory='%APPDIR%'; $s.IconLocation='%SystemRoot%\System32\SHELL32.dll,44'; $s.Save()" >nul 2>&1

echo.
echo   Installed. A "SpeedRunner" icon is now on the Desktop - use it next time.
echo.

:run
cd /d "%APPDIR%"
call "%APPDIR%\run_app.bat"
