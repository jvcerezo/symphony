@echo off
rem Fetches the tools the bot uses on Windows into tools\ (once), and keeps
rem yt-dlp current. Called by start-windows.cmd.
setlocal
set "POT_VERSION=2.0.2"
set "TOOLS=%~dp0tools"
if not exist "%TOOLS%\yt-dlp-plugins" mkdir "%TOOLS%\yt-dlp-plugins"

if not exist "%TOOLS%\yt-dlp.exe" (
  echo Downloading yt-dlp...
  curl -fsSL -o "%TOOLS%\yt-dlp.exe" https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe || exit /b 1
) else (
  "%TOOLS%\yt-dlp.exe" -U >nul 2>&1
)

rem The yt-dlp plugin that asks the PO token helper for YouTube's proof.
if not exist "%TOOLS%\yt-dlp-plugins\bgutil-ytdlp-pot-provider.zip" (
  curl -fsSL -o "%TOOLS%\yt-dlp-plugins\bgutil-ytdlp-pot-provider.zip" https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/%POT_VERSION%/bgutil-ytdlp-pot-provider.zip || exit /b 1
)

rem The PO token helper itself, built from its release.
if not exist "%TOOLS%\pot\build\main.js" (
  echo Setting up the PO token helper, one time only...
  if exist "%TOOLS%\pot" rmdir /s /q "%TOOLS%\pot"
  mkdir "%TOOLS%\pot"
  curl -fsSL -o "%TOOLS%\pot.tar.gz" https://github.com/Brainicism/bgutil-ytdlp-pot-provider/archive/refs/tags/%POT_VERSION%.tar.gz || exit /b 1
  tar -xzf "%TOOLS%\pot.tar.gz" -C "%TOOLS%\pot" --strip-components=2 "bgutil-ytdlp-pot-provider-%POT_VERSION%/server" || exit /b 1
  del "%TOOLS%\pot.tar.gz"
  pushd "%TOOLS%\pot"
  call npm ci --no-audit --no-fund >nul || (popd & exit /b 1)
  call npx tsc || (popd & exit /b 1)
  call npm prune --omit=dev --no-audit --no-fund >nul
  popd
)
exit /b 0
