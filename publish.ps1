#Requires -Version 5.1
<#
.SYNOPSIS
    IPプリセット (IpPreset) を Windows x64 向けの自己完結・単一ファイル実行形式(exe)として発行します。

.DESCRIPTION
    dotnet publish を用いて、win-x64 / 自己完結 (self-contained) / シングルファイルの
    dist\IpPreset.exe を生成します。coworker への配布方法は DISTRIBUTE.md を参照してください。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\publish.ps1
#>
param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "=== IPプリセット 発行スクリプト ===" -ForegroundColor Cyan

if (Test-Path $OutputDir) {
    Write-Host "既存の $OutputDir フォルダを削除します..."
    Remove-Item $OutputDir -Recurse -Force
}

dotnet publish "src/IpPreset/IpPreset.csproj" `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=none `
    -o $OutputDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "発行に失敗しました。上記のログを確認してください。"
    exit 1
}

Copy-Item "presets.example.json" (Join-Path $OutputDir "presets.example.json") -Force
Copy-Item "setup.cmd" (Join-Path $OutputDir "setup.cmd") -Force
Copy-Item "README.md" (Join-Path $OutputDir "README.md") -Force

Write-Host ""
Write-Host "発行が完了しました: $OutputDir\IpPreset.exe" -ForegroundColor Green
Write-Host "coworkerへの配布方法は DISTRIBUTE.md を参照してください。"
