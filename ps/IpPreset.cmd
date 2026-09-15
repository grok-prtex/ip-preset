@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"

rem Mark of the Web (ダウンロードブロック) を外してから起動します。
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Unblock-File -LiteralPath '%HERE%IpPreset.ps1' -ErrorAction SilentlyContinue; Unblock-File -LiteralPath '%HERE%IpPreset-launch.vbs' -ErrorAction SilentlyContinue } catch { }"

rem -ListPresets はコンソール出力が必要なので通常起動。GUI / -Preset は VBS でコンソール非表示。
echo %*| find /I "-ListPresets" >nul
if not errorlevel 1 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%IpPreset.ps1" %*
  set "EC=%ERRORLEVEL%"
  endlocal & exit /b %EC%
)

wscript //nologo "%HERE%IpPreset-launch.vbs" %*
endlocal & exit /b 0
