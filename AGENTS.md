# AGENTS.md

## 目的
- このファイルは、AIエージェントが Logleaf リポジトリで安全に実装・修正するための実務ルールを定義します。
- GitHub Copilot や各種 AI ツールが本リポジトリのコンテキストを理解しやすくするためのガイドです。
- 新しい機能を実装する際はここで示す技術選定・設計方針・モジュール構成を前提にしてください。
- 不確かな点がある場合は、リポジトリのファイルを探索し、ユーザーに「こういうことですか?」と確認をするようにしてください。

## 前提条件
- 回答は必ず日本語でしてください。
- コードレビューの結果も日本語でしてください．

## プロジェクト概要
- Logleaf はローカル完結の macOS 作業記録アプリです。
- 定期スクリーンショットからローカルVLM推論を行い、タグ付き作業記録を生成します。
- 主要価値は、プライバシー保護と実運用での安定性です。

## 技術スタック
- Swift / SwiftUI / Swift Package Manager
- GRDB / SQLite
- ScreenCaptureKit など macOS API
- Ollama ローカルHTTP API
- XCTest

## 作業ルール
- 近傍コードを読んで既存スタイルに合わせる。
- 問題を根本原因から直し、場当たり対応を避ける。
- 変更範囲は最小化し、レイヤ越境をしない。
- `Infrastructure`, `Services`, `Repositories`, `ViewModels` の責務を保つ。
- ローカル完結方針を壊す依存（外部SaaS送信など）を追加しない。

## 構成マップ
- `Sources/Logleaf/`: 実行ターゲット、起動処理
- `Sources/LogleafLib/Database`: DB初期化、マイグレーション
- `Sources/LogleafLib/Infrastructure`: 外部連携、ファイル、ログ、推論クライアント
- `Sources/LogleafLib/Models`: ドメインモデル
- `Sources/LogleafLib/Repositories`: 永続化層
- `Sources/LogleafLib/Services`: 業務ロジック
- `Sources/LogleafLib/ViewModels`: UIロジック
- `Sources/LogleafLib/Views`: 画面
- `Tests/LogleafTests`: テスト

## 検証要件
- 挙動に影響する変更では `swift build` を実施する。
- ロジック変更では `swift test` を実施する。
- テスト未実施の場合は理由を明記する。
- DB変更時はマイグレーションと read/write 経路の整合を確認する。

## 回答フォーマット要件
- 変更概要を簡潔に示す。
- 変更ファイル一覧を示す。
- 実行した検証コマンドと結果を示す。
- 残るリスク・前提・次アクションを示す。

## 便利コマンド
- `swift build`
- `swift test`
- `swift run Logleaf`
