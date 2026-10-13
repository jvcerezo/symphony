@echo off
rem Starts the Symphony Discord bot on this PC. Close this window to stop it.
setlocal
title Symphony Discord Bot
cd /d "%~dp0"

if not exist ".env" (
  echo No .env file here. Copy .env.example to .env and add your bot token.
  pause
  exit /b 1
)
if not exist "node_modules" (
  echo Installing the bot's packages, one time only...
  call npm install --no-fund --no-audit || (pause & exit /b 1)
)

call "%~dp0setup-tools.cmd" || (echo Could not set up the tools the bot needs. & pause & exit /b 1)
set "YTDLP_PATH=%~dp0tools\yt-dlp.exe"
set "POT_SERVER_SCRIPT=%~dp0tools\pot\build\main.js"

echo Symphony is starting. Leave this window open while you listen; close it to stop the bot.
echo.
call npm start
if errorlevel 2 if not errorlevel 3 (
  timeout /t 5 >nul
  exit /b 0
)
echo.
echo The bot stopped.
pause
