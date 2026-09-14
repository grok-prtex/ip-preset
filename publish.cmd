@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo === IPプリセット 発行スクリプト ===

set "OUTDIR=dist"

if exist "%OUTDIR%" (
    echo 既存の %OUTDIR% フォルダを削除します...
    rmdir /s /q "%OUTDIR%"
)

dotnet publish "src\IpPreset\IpPreset.csproj" ^
    -c Release ^
    -r win-x64 ^
    --self-contained true ^
    -p:PublishSingleFile=true ^
    -p:IncludeNativeLibrariesForSelfExtract=true ^
    -p:EnableCompressionInSingleFile=true ^
    -p:DebugType=none ^
    -o "%OUTDIR%"

if errorlevel 1 (
    echo.
    echo 発行に失敗しました。上記のログを確認してください。
    exit /b 1
)

copy /y "presets.example.json" "%OUTDIR%\presets.example.json" >nul
copy /y "setup.cmd" "%OUTDIR%\setup.cmd" >nul
copy /y "README.md" "%OUTDIR%\README.md" >nul

echo.
echo 発行が完了しました: %OUTDIR%\IpPreset.exe
echo coworkerへの配布方法は DISTRIBUTE.md を参照してください。

endlocal
