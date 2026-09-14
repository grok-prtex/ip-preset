# 開発者向けドキュメント (IpPreset)

このドキュメントは `IPプリセット` (IpPreset) の開発・ビルド・テストに関する情報をまとめたものです。
利用者向けの使い方は [`README.md`](../README.md)、配布方法は [`DISTRIBUTE.md`](../DISTRIBUTE.md) を参照してください。


## 0. 配布の主成果物（PowerShell）

エンドユーザー向けの推奨配布は [`ps/`](../ps/) です（SmartScreen 回避）。  
C# WinForms / `dotnet publish` は開発・互換用にリポジトリへ残していますが、Release の主アセットは `IpPreset-win.zip`（`ps/` の中身）です。

## 1. 技術スタック

- .NET 8 (SDK 8.0系)
- WinForms（`net8.0-windows`）
- PowerShell（`Set-NetIPInterface` / `New-NetIPAddress` / `Set-DnsClientServerAddress` 等）をサブプロセスとして呼び出し、実際のIP設定変更を行います
- xUnit（ユニットテスト）

## 2. プロジェクト構成

```
IpPreset.sln
src/
  IpPreset.Core/         … UIに依存しないロジック層（net8.0、クロスプラットフォームでビルド可能）
    Models/
      NetworkPreset.cs   … プリセットのデータモデル
    Net/
      AdapterInfo.cs     … アダプター一覧・現在のIP設定の表示用モデル
      NetworkInfoService.cs … アダプター一覧・現在の状態の取得（読み取り専用）
      IpUtils.cs         … サブネットマスク/プレフィックス長の相互変換、IPv4バリデーション
      IpApplyScript.cs   … 実際にIPを変更するPowerShellスクリプトの中身（固定テンプレート）
      IpApplyExecutor.cs … 上記スクリプトを引数付きで実行するロジック
      IpApplyResult.cs   … 適用結果
    PresetStore.cs        … presets.json の読み書き
    PresetValidator.cs    … プリセット入力値の検証
    DefaultPresets.cs     … 初回起動時のサンプルプリセット
  IpPreset/               … WinFormsアプリ本体（net8.0-windows）
    Program.cs
    MainForm.cs           … メイン画面
    PresetEditForm.cs     … プリセット追加・編集ダイアログ
    AppTheme.cs           … アクセントカラー定義（ジェイド #0E9E6B のみ）
    app.manifest          … 管理者権限を要求するアプリケーションマニフェスト
tests/
  IpPreset.Tests/         … IpPreset.Core に対するユニットテスト（net8.0、Windows不要で実行可能）
presets.example.json      … プリセットのサンプルファイル
publish.ps1 / publish.cmd … 発行スクリプト
setup.cmd                 … 配布先でのデスクトップショートカット作成スクリプト
```

`IpPreset.Core` は Windows専用APIを直接呼び出す部分（`NetworkInfoService` の DHCP判定など）を除き、
できる限りcrossプラットフォームでビルド・テスト可能な形にしてあります。これにより、
Windows環境が無いCI（Linux等）でもロジック部分のユニットテストを実行できます。

## 3. ビルド

.NET 8 SDKをインストールした上で、リポジトリルートで以下を実行します。

```bash
dotnet build IpPreset.sln
```

> **Linux/macOS上でビルドする場合の注意:** `IpPreset.csproj` は `net8.0-windows`
> (WinForms) をターゲットにしていますが、`EnableWindowsTargeting=true` を設定しているため、
> Windows以外のSDKでも**ビルド**は可能です（コンパイルのみ。実行にはWindowsが必要です）。

## 4. テスト

```bash
dotnet test tests/IpPreset.Tests/IpPreset.Tests.csproj
```

`IpPreset.Core` のロジック（IPアドレス/サブネットマスク変換、プリセットのバリデーション、
`presets.json` の読み書き、PowerShell呼び出し引数の組み立て）をユニットテストで検証しています。
PowerShellの実行そのもの（実機のNIC設定変更）はWindows実機での手動確認が必要です。
`README.md` の「手動テストチェックリスト」を参照してください。

## 5. 発行 (publish)

```powershell
powershell -ExecutionPolicy Bypass -File .\publish.ps1
```

または

```bat
publish.cmd
```

`win-x64` 向けに自己完結 (self-contained) ・シングルファイルの `dist/IpPreset.exe` を生成します。
詳細は [`DISTRIBUTE.md`](../DISTRIBUTE.md) を参照してください。

## 6. 設計上の主な判断

- **管理者権限:** アプリ起動時に常に管理者権限を要求する方式（`app.manifest` の
  `requestedExecutionLevel="requireAdministrator"`）を採用しました。NIC設定変更は必ず管理者権限が
  必要になるため、「必要なときだけ昇格」を実装するよりも、起動時に一括で昇格させたほうが
  実装がシンプルかつ確実（権限不足による中途半端な失敗を避けられる）と判断したためです。
- **IP設定変更の実装方式:** `System.Net.NetworkInformation` は読み取り専用のAPIしか提供していないため、
  実際の変更には `NetTCPIP` PowerShellモジュール（`Set-NetIPInterface` / `New-NetIPAddress` /
  `Set-DnsClientServerAddress`）をサブプロセスとして呼び出しています。値はすべて
  `ProcessStartInfo.ArgumentList` 経由（文字列連結なし）で渡しており、コマンドインジェクションの
  リスクを避けています。
- **presets.json の保存場所:** 実行ファイルと同じフォルダに保存する方式を採用しました。
  USBメモリ等でのポータブル運用を優先しています。
- **UIフレームワーク:** 要件がWindows専用の管理者ツールであり、デザイン要件も「プレーンでよい」
  とされていたため、軽量なWinFormsを採用しました（WPFほどの表現力は不要なため）。

## 7. 既知の制約

- IPv6の設定変更には対応していません（読み取り・変更ともにIPv4のみを対象としています）。
- Wi-Fiプロファイルの切り替えやVPN設定には対応していません。
- コード署名は行っていないため、配布先PCでWindows Defender SmartScreenの警告が出ることがあります
  （`DISTRIBUTE.md` 参照）。
