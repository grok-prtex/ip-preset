# 配布方法 (DISTRIBUTE)

`IPプリセット` (IpPreset) を同僚（coworker）や現場PCへ配布するための手順です。  
インストーラは使用しません。**推奨成果物は PowerShell GUI の Zip** です（署名なし exe の SmartScreen を避けるため）。

## 0. 【推奨】GitHub Releases から取得する

[`.github/workflows/release.yml`](.github/workflows/release.yml) により、`v*` タグの push または workflow_dispatch で次を行います。

1. `ps/` 配下（`IpPreset.ps1` / `IpPreset.cmd` / `setup.cmd` / `presets.example.json` / `README.md`）を `IpPreset-win.zip` にまとめる
2. タグ実行時は GitHub Releases のアセットとしてアップロード

**入手手順:**

1. リポジトリの **Releases** ページを開く
2. 最新の `IpPreset-win.zip` をダウンロードする
3. 任意のフォルダに展開する
4. `setup.cmd`（推奨）または `IpPreset.cmd` を実行する

新しいリリース例:

```bash
git tag v0.2.0
git push origin v0.2.0
```

タグなしで Zip だけ欲しい場合は Actions の「Release」を `workflow_dispatch` で手動実行してください（Artifact のみ）。

> C# の単一 exe はリポジトリに残していますが、**Release の主アセットには含めません**（SmartScreen 回避のため）。ローカルで exe を試す場合は従来どおり `publish.ps1` を使えます。

## 1. ローカルで Zip を作る場合

リポジトリルートで:

```powershell
New-Item -ItemType Directory -Path dist -Force | Out-Null
Copy-Item ps\* dist\ -Force
Compress-Archive -Path dist\* -DestinationPath IpPreset-win.zip -Force
```

中身のイメージ:

```
IpPreset.cmd           … ダブルクリック用ランチャー（Bypass + Unblock + STA）
IpPreset.ps1           … WinForms GUI
setup.cmd              … Unblock 全ファイル + デスクトップショートカット
presets.example.json   … サンプル
README.md              … 短い使い方
```

## 2. 受け取った側（現場PC）でのセットアップ

1. Zip を展開する
2. **初回:** `setup.cmd` をダブルクリック（ブロック解除 + ショートカット）
3. `IpPreset.cmd` またはショートカットで起動（起動時 UAC なし）
4. 「適用」時だけ UAC で管理者承認

スクリプトが実行できないとき:

- `setup.cmd` を再実行する
- または `IpPreset.ps1` を右クリック → プロパティ → 「許可する」

`IpPreset.cmd` は `-ExecutionPolicy Bypass` で起動するため、マシン全体の ExecutionPolicy を緩める必要はありません。

## 3. USB メモリでのポータブル運用

プリセットは `presets.json` として **スクリプトと同じフォルダ** に保存されます。  
フォルダ一式（少なくとも `IpPreset.cmd` / `IpPreset.ps1` / `presets.json`）を一緒にコピーすれば、複数の現場PCで同じ一覧を使えます。

## 4. アンインストール

展開したフォルダを削除するだけです。`setup.cmd` で作ったデスクトップショートカットも削除してください。

## 5. SmartScreen / Defender について

| 配布物 | SmartScreen（青い警告） | UAC |
|---|---|---|
| **PowerShell Zip（推奨）** | 通常出ない | 適用時のみ |
| 署名なし .NET 単一 exe | 出やすい | 起動時または適用時 |

コード署名証明書の購入は不要です。社内ポリシーでスクリプト実行が禁止されている場合は、IT 担当に相談してください。
