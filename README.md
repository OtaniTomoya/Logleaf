# Logleaf

Logleaf は、macOS 上で定期スクリーンショットを取得し、ローカル AI 推論で作業内容をタグ付きで記録するローカル完結型の作業ログアプリです。データはユーザー環境内に保存され、外部 SaaS 送信を前提にしません。

## 主な機能

- メニューバー常駐アプリとして起動
- 定期スクリーンショット取得（収録は常時）
- ボタン実行による手動一括 AI 推論
- Ollama を使ったローカル VLM 推論（推論時のみ起動/利用）
- 日次タイムライン表示
- 週次・月次サマリ表示
- タグ管理と除外ルール管理
- CSV / Markdown / JSON エクスポート
- トラブルシュート画面から権限・接続・保存先を確認

## 技術スタック

- Swift 5.9
- SwiftUI
- Swift Package Manager
- GRDB / SQLite
- ScreenCaptureKit
- Ollama Local API
- XCTest

## 動作要件

- macOS 14 以降
- Xcode 15 系、または同等の Swift 5.9 ツールチェーン
- Ollama CLI がインストール済みであること
- 画面収録権限
- アクセシビリティ権限
  - 任意。ウィンドウタイトル取得のために使用

## Ollama 前提

- 接続先のデフォルトは `http://localhost:11434`
- モデル設定のデフォルトは `gemma4:e4b`
- メニューの「溜まった画像を推論」実行時のみ推論を行い、必要に応じてローカル Ollama を起動します
- 初回セットアップ中の接続テストでは、起動中の Ollama から利用可能モデル一覧を取得します
- 利用したいモデルが一覧に出ない場合は、事前に Ollama 側で取得しておく必要があります

例:

```bash
ollama pull gemma4:e4b
ollama list
```

## セットアップ

1. 使用するモデルを取得する
   最低限、セットアップで選択するモデルがローカルに存在している必要があります

```bash
ollama pull gemma4:e4b
```

2. パッケージをビルドする

```bash
swift build
```

3. アプリを起動する

```bash
swift run Logleaf
```

4. 初回セットアップを完了する

セットアップ画面では以下を順に行います。

- 画面収録権限の許可
- アクセシビリティ権限の許可
  - 任意です。未許可でも基本機能は使えます
- Ollama 接続テスト
  - このタイミングでは Ollama を起動しておく必要があります
- 使用モデルの選択
- 保存期間の設定
- 初期タグの登録
  - 1つ以上のタグ登録が必要です

初期設定の既定値:

- キャプチャ間隔: 60秒
- チェックポイント間隔: 5分
- Ollama ホスト: `http://localhost:11434`
- Ollama モデル: `gemma4:e4b`
- 保存期間: 30日
- 自動削除: 有効

セットアップ完了後は設定画面から以下を変更できます。

- キャプチャ間隔
- チェックポイント間隔
- Ollama ホスト
- Ollama モデル
- 保存期間
- 自動削除の有効 / 無効

## 開発

ビルド:

```bash
swift build
```

テスト:

```bash
swift test
```

Xcode で開発する場合は、リポジトリを Swift Package としてそのまま開けます。

## 保存先

アプリのデータはリポジトリ直下ではなく、以下に保存されます。

`~/Library/Application Support/Logleaf/`

保存内容:

- `logleaf.sqlite`: SQLite データベース
- `screenshots/`: 取得したスクリーンショット
- `exports/`: エクスポート結果
- `logs/`: アプリ用ログ保存先

## リポジトリ構成

- `Sources/Logleaf/`: アプリ起動処理
- `Sources/LogleafLib/`: ドメイン、DB、サービス、UI 実装
- `Tests/LogleafTests/`: テスト
- `tasks.md`: 開発タスクリスト
- `tasks/todo.md`: 今回の作業計画とレビュー

## 現状メモ

- パッケージ定義は SwiftPM ベースで、`Package.resolved` は追跡対象です
- `.gitignore` は macOS / SwiftPM / Xcode のローカル生成物を除外します
- 生成データは Application Support 配下に保存されるため、通常は Git 管理対象になりません
