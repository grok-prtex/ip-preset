@echo off
chcp 65001 >nul
setlocal

rem このファイルは IpPreset.exe と同じフォルダに置いて実行してください。
rem デスクトップに「IPプリセット」のショートカットを作成します（インストーラは使用しません）。

set "HEREDIR=%~dp0"
set "EXE=%HEREDIR%IpPreset.exe"
set "SHORTCUT=%USERPROFILE%\Desktop\IPプリセット.lnk"

if not exist "%EXE%" (
    echo [エラー] IpPreset.exe が見つかりません。
    echo このファイルを IpPreset.exe と同じフォルダに置いてから実行してください。
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$s = New-Object -ComObject WScript.Shell;" ^
    "$sc = $s.CreateShortcut('%SHORTCUT%');" ^
    "$sc.TargetPath = '%EXE%';" ^
    "$sc.WorkingDirectory = '%HEREDIR%';" ^
    "$sc.Description = 'IPプリセット - ネットワークIP設定切り替えツール';" ^
    "$sc.Save()"

if errorlevel 1 (
    echo [エラー] ショートカットの作成に失敗しました。
    pause
    exit /b 1
)

echo デスクトップに「IPプリセット」のショートカットを作成しました。
echo アイコンをダブルクリックして起動してください（起動時にUAC確認が表示されます）。
pause

endlocal
