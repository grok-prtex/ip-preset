# IPプリセット（PowerShell 版）

Windows のネットワークアダプター IPv4 設定を、名前付きプリセットで切り替えるツールです。

## 起動方法

1. このフォルダを任意の場所に置きます（USB でも可）。
2. **初回のみ推奨:** `setup.cmd` をダブルクリック  
   → ダウンロードブロック解除 + デスクトップショートカット作成
3. `IpPreset.cmd`（またはショートカット）をダブルクリックして起動します。

`IpPreset.cmd` は `ExecutionPolicy Bypass` と `Unblock-File` を行い、`IpPreset.ps1` を STA で起動します。

## SmartScreen について

署名なしの `.exe` は SmartScreen（青い「PCが保護されました」）の対象になりやすいです。  
本配布は **PowerShell スクリプト + .cmd** のため、その青い警告を避けられます。  
IP 設定の変更時だけ UAC（管理者承認）が出ます。

スクリプトが「実行できない」場合は `setup.cmd` を実行するか、エクスプローラーで `IpPreset.ps1` を右クリック → プロパティ → 「許可する」にチェックしてください。

## 使い方（要約）

1. ネットワークアダプターを選ぶ
2. プリセットを追加・編集（DHCP / 静的）
3. 「適用」→ 確認ダイアログ →（必要なら）UAC で承認

設定は同じフォルダの `presets.json` に保存されます。サンプルは `presets.example.json` です。

## コマンドライン（CLI）

`IpPreset.cmd` に引数を渡すと、GUI を開かずに操作できます。

```bat
rem プリセット一覧（名前とモード）を表示して終了
IpPreset.cmd -ListPresets

rem プリセット名で適用（アダプター選択ダイアログ → UAC）
IpPreset.cmd -Preset "工場A"
IpPreset.cmd -Preset "自動" 
```

- `-Preset` は名前の完全一致（大文字小文字無視）、なければ一意な前方一致で解決します。
- 適用先アダプターはダイアログで選びます（一覧は `[1] 名前  [状態]` 形式。GUI のコンボも同様）。
- `-ListPresets` はコンソール出力のみ（GUI なし）。

## 要件

- Windows 10 / 11
- PowerShell 5.1（標準添付）
