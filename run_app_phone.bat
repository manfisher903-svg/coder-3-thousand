@echo off
REM Launch SpeedRunner so your PHONE can open it over Wi-Fi.
REM Watch this window — it prints the http://...:5000 address to type on your phone.
cd /d "%~dp0"
python -m pip install -q -r requirements.txt
python -m scanner.update
set PIS_LAN=1
python -m scanner.app
pause
