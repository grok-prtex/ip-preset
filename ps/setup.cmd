@echo off
chcp 65001 >nul
setlocal

rem このフォルダ内のスクリプトのブロックを解除し、デスクトップにショートカットを作成します。

set "HEREDIR=%~dp0"
set "LAUNCHER=%HEREDIR%IpPreset.cmd"
set "SHORTCUT=%USERPROFILE%\Desktop\IPプリセット.lnk"

if not exist "%LAUNCHER%" (
    echo [エラー] IpPreset.cmd が見つかりません。
    echo このファイルを IpPreset.cmd と同じフォルダに置いてから実行してください。
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Get-ChildItem -LiteralPath '%HEREDIR%' -File | Unblock-File -ErrorAction SilentlyContinue;" ^
    "$s = New-Object -ComObject WScript.Shell;" ^
    "$sc = $s.CreateShortcut('%SHORTCUT%');" ^
    "$sc.TargetPath = '%LAUNCHER%';" ^
    "$sc.WorkingDirectory = '%HEREDIR%';" ^
    "$sc.Description = 'IPプリセット - ネットワークIP設定切り替えツール (PowerShell)';" ^
    "$sc.Save()"

if errorlevel 1 (
    echo [エラー] ショートカットの作成に失敗しました。
    pause
    exit /b 1
)

echo フォルダ内のファイルのブロックを解除し、
echo デスクトップに「IPプリセット」のショートカットを作成しました。
echo.
echo 起動: IpPreset.cmd（またはデスクトップのショートカット）をダブルクリック
echo 適用時のみ UAC（管理者承認）が表示されます。SmartScreen の青い警告は出ません。
pause

endlocal
