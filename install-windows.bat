@echo off
REM ============================================================
REM  SpeedRunner - one-click installer for Windows.
REM  Give this ONE file to someone. They double-click it - that's it.
REM  Nothing needs to be installed first: this downloads the app AND
REM  its own private copy of Python into one folder, then launches it.
REM  From then on it auto-updates every time it opens.
REM ============================================================
setlocal enabledelayedexpansion
title SpeedRunner Installer
cd /d "%~dp0"

set "APPDIR=%LOCALAPPDATA%\SpeedRunner"
set "CODE_URL=https://github.com/manfisher903-svg/coder-3-thousand/archive/refs/heads/claude/personal-info-scanner-rwixso.zip"
set "PY_URL=https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip"
set "PIP_URL=https://bootstrap.pypa.io/get-pip.py"

echo.
echo   Installing SpeedRunner - this is fully automatic.
echo   Location: %APPDIR%
echo.

REM --- 1) download + extract the app code ---
if not exist "%APPDIR%\scanner\app.py" (
  echo   [1/3] Downloading SpeedRunner...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $z=Join-Path $env:TEMP 'sr_code.zip'; Invoke-WebRequest -Uri '%CODE_URL%' -OutFile $z; $t=Join-Path $env:TEMP 'sr_code'; if(Test-Path $t){Remove-Item $t -Recurse -Force}; Expand-Archive $z $t -Force; $inner=(Get-ChildItem $t | Select-Object -First 1).FullName; New-Item -ItemType Directory -Force -Path '%APPDIR%' | Out-Null; Copy-Item (Join-Path $inner '*') '%APPDIR%' -Recurse -Force; Remove-Item $z -Force"
  if errorlevel 1 ( echo   Download failed - check the internet connection and try again. & pause & exit /b 1 )
)

REM --- 2) set up a private Python inside the app folder (one time) ---
if not exist "%APPDIR%\python\python.exe" (
  echo   [2/3] Setting up Python ^(one time, about 15 MB^)...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $z=Join-Path $env:TEMP 'sr_py.zip'; Invoke-WebRequest -Uri '%PY_URL%' -OutFile $z; $d=Join-Path '%APPDIR%' 'python'; if(Test-Path $d){Remove-Item $d -Recurse -Force}; Expand-Archive $z $d -Force; Remove-Item $z -Force; $pth=(Get-ChildItem $d -Filter 'python*._pth' | Select-Object -First 1).FullName; (Get-Content $pth) -replace '#\s*import\s+site','import site' | Set-Content $pth; $gp=Join-Path $d 'get-pip.py'; Invoke-WebRequest -Uri '%PIP_URL%' -OutFile $gp; & (Join-Path $d 'python.exe') $gp --no-warn-script-location -q"
  if errorlevel 1 ( echo   Python setup failed - check the internet connection and try again. & pause & exit /b 1 )
)

REM --- 3) install the app's components into that private Python ---
echo   [3/3] Installing components...
"%APPDIR%\python\python.exe" -m pip install -q -r "%APPDIR%\requirements.txt"

REM --- put a clickable icon on the Desktop AND in the Start Menu ---
REM (Start Menu entries can be right-clicked and pinned to the taskbar.)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$w=New-Object -ComObject WScript.Shell; foreach($p in @([IO.Path]::Combine([Environment]::GetFolderPath('Desktop'),'SpeedRunner.lnk'),[IO.Path]::Combine([Environment]::GetFolderPath('Programs'),'SpeedRunner.lnk'))){ $s=$w.CreateShortcut($p); $s.TargetPath=Join-Path '%APPDIR%' 'run_app.bat'; $s.WorkingDirectory='%APPDIR%'; $s.IconLocation='%SystemRoot%\System32\SHELL32.dll,44'; $s.Save() }" >nul 2>&1

echo.
echo   Done! A "SpeedRunner" icon is on your Desktop and in the Start Menu.
echo.
echo   To PIN it to your taskbar: open the Start menu, type SpeedRunner,
echo   right-click it, and choose "Pin to taskbar".
echo.
echo   Starting SpeedRunner now...
echo.
cd /d "%APPDIR%"
call "%APPDIR%\run_app.bat"
