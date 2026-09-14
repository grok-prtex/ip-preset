@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"

rem Mark of the Web (ダウンロードブロック) を外してから起動します。
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Unblock-File -LiteralPath '%HERE%IpPreset.ps1' -ErrorAction SilentlyContinue } catch { }"

powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%IpPreset.ps1" %*
set "EC=%ERRORLEVEL%"
endlocal & exit /b %EC%
