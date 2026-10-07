@echo off
REM Double-click to open the Personal Info Scanner app (Windows).
cd /d "%~dp0"
python -m pip install -q -r requirements.txt
python -m scanner.app
pause
