@echo off
REM Double-click to launch SpeedRunner (Windows) — opens in your browser.
cd /d "%~dp0"
python -m pip install -q -r requirements.txt
python -m scanner.app
pause
