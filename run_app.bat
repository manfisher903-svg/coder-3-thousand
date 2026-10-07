@echo off
REM Double-click to launch SpeedRunner (Windows) — opens in your browser.
REM It auto-updates to the latest version first (your accounts and scans are kept).
cd /d "%~dp0"
python -m pip install -q -r requirements.txt
echo Checking for updates...
python -m scanner.update
python -m scanner.app
pause
