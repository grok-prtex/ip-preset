# 配布方法 (DISTRIBUTE)

`IPプリセット` (IpPreset) を同僚（coworker）や現場PCへ配布するための手順です。
インストーラ（MSI等）は使用しません。exeファイルをそのまま配布します。

## 0. 【推奨】GitHub Releases から取得する

このリポジトリには [`.github/workflows/release.yml`](.github/workflows/release.yml) が用意されており、
`v*` 形式のタグ（例: `v1.0.0`）をpushする、または GitHub Actions の画面から手動実行 (workflow_dispatch)
すると、自動的に以下を行います。

1. `windows-latest` 上でユニットテストを実行
2. `win-x64` 向けに自己完結・シングルファイルで `dotnet publish`
3. `IpPreset.exe` / `setup.cmd` / `presets.example.json` / `README.md` / `DISTRIBUTE.md` を
   `IpPreset-win-x64.zip` にまとめる
4. タグからの実行の場合、その内容を **GitHub Releases** のアセットとしてアップロード

そのため、**推奨される配布・入手手順は以下の通りです。**

1. リポジトリの **Releases** ページを開く
2. 最新のリリースから `IpPreset-win-x64.zip` をダウンロードする
3. 任意のフォルダに展開（解凍）する
4. `setup.cmd`（デスクトップショートカット作成、任意）または `IpPreset.exe` を直接実行する

新しいリリースを作りたい場合は、リポジトリに `v1.0.0` のようなタグをpushしてください。

```bash
git tag v1.0.0
git push origin v1.0.0
```

タグを付けずに動作確認だけしたい場合は、GitHub Actionsの「Release」ワークフローを
`workflow_dispatch` で手動実行してください（Release作成はスキップされ、Zipは
ワークフローのArtifactとしてダウンロードできます）。

> GitHubにリポジトリがまだ無い、またはActionsが利用できない場合は、
> 以下の「1. 発行（publish）する」以降の手順でローカルから手動発行してください。

## 1. 発行（publish）する（ローカルで手動発行する場合）

開発機（Windows / dotnet SDK がインストールされている環境）で、リポジトリのルートにある
発行スクリプトを実行します。

### PowerShellの場合

```powershell
powershell -ExecutionPolicy Bypass -File .\publish.ps1
```

### コマンドプロンプトの場合

```bat
publish.cmd
```

いずれも、以下のファイルが `dist` フォルダに生成されます。

```
dist/
  IpPreset.exe          … 本体（自己完結・シングルファイル。これ1つで動作します）
  presets.example.json  … プリセットのサンプル
  setup.cmd             … デスクトップショートカット作成用（任意）
  README.md             … 使い方
```

`IpPreset.exe` は約60〜70MB程度になります（.NETランタイムを内包した自己完結ファイルのため）。
これは正常です。

## 2. Zipにまとめる

`dist` フォルダの中身をそのままZip圧縮します。

- Windowsのエクスプローラーで `dist` フォルダを開く
- フォルダ内の全ファイルを選択 → 右クリック →「送る」→「圧縮 (zip 形式) フォルダー」
- 生成されたZipファイルの名前を `IpPreset_v1.0.0.zip` のように、バージョンが分かる名前に変更する

> **ポイント:** `dist` フォルダ自体ではなく、**フォルダの中身**をZip化してください。
> 解凍したときに `IpPreset.exe` が直接見える状態が理想です（フォルダが二重にならないように）。

PowerShellでコマンド一発で作りたい場合は、以下でも構いません。

```powershell
Compress-Archive -Path .\dist\* -DestinationPath .\IpPreset_v1.0.0.zip -Force
```

## 3. 同僚に渡す

作成したZipファイルを、社内共有フォルダ・チャット・USBメモリなど、普段お使いの方法で渡してください。
インターネット経由の共有サービスを使う場合は、社内ポリシーに従ってください。

## 4. 受け取った側（現場PC）でのセットアップ

GitHub Releasesからダウンロードした場合も、同僚から手渡しされた場合も、手順は同じです。

1. 入手したZipファイル（`IpPreset-win-x64.zip` など）を、任意のフォルダ
   （デスクトップやUSBメモリ内など）に展開（解凍）します。
2. （任意）`setup.cmd` をダブルクリックすると、デスクトップに「IPプリセット」のショートカットが作成されます。
   - `setup.cmd` は `IpPreset.exe` と同じフォルダに置いた状態で実行してください。
   - ショートカットが不要な場合は、`IpPreset.exe` を直接ダブルクリックしても起動できます。
3. `IpPreset.exe`（またはショートカット）を起動します。
4. UAC（ユーザーアカウント制御）の確認画面が表示されたら「はい」を選択してください
   （NICの設定変更には管理者権限が必須のため、このツールは常に管理者として起動します）。

## 5. USBメモリでのポータブル運用について

このツールはプリセットを `presets.json` として **実行ファイルと同じフォルダ** に保存します。
そのため、`IpPreset.exe` と `presets.json` を一緒にUSBメモリへコピーしておけば、
複数の現場PCに同じプリセット一覧を持ち運んで使うことができます。

## 6. アンインストール

インストーラを使用していないため、「アンインストール」という概念はありません。
展開したフォルダ（`IpPreset.exe` や `presets.json` を含むフォルダ）を削除するだけで完了です。
`setup.cmd` でデスクトップショートカットを作成した場合は、そのショートカットも合わせて削除してください。

## 7. Windows Defender / SmartScreen について

自己署名（コード署名なし）の実行ファイルを配布・実行すると、Windows Defender SmartScreenの警告
（「WindowsによってPCが保護されました」等）が表示されることがあります。
社内配布物として問題ない場合は、「詳細情報」→「実行」を選択して起動してください。
社内でコード署名証明書を運用している場合は、`IpPreset.exe` に署名してから配布することをおすすめします。
