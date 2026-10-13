@echo off
chcp 65001 >nul
cd /d %~dp0
REM Anahtarlar (bir kez): setx GEMINI_API_KEY "..."  ve istege bagli: setx ELEVENLABS_API_KEY "..."
REM Port/kamera: python robot_beyin.py --port COM3 --kamera 1 --mic "Mikrofon (Logi C270 HD WebCam)"
python robot_beyin.py --yuztakip 0 %*
pause
