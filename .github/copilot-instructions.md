# Logleaf Copilot Instructions

## このドキュメントについて

- GitHub Copilot や各種 AI ツールが本リポジトリのコンテキストを理解しやすくするためのガイドです。
- 新しい機能を実装する際はここで示す技術選定・設計方針・モジュール構成を前提にしてください。
- 不確かな点がある場合は、リポジトリのファイルを探索し、ユーザーに「こういうことですか?」と確認をするようにしてください。

## 前提条件
- 回答は必ず日本語でしてください。

## 1. プロジェクト概要
- Logleaf は、macOS のメニューバー常駐で作業記録を自動生成するローカル完結型アプリです。
- おおむね1分ごとに画面を取得し、Ollama 経由のローカルVLMで作業内容とタグを推定します。
- 推定結果を SQLite に保存し、日次タイムラインやセッションとして可視化・手動修正できることが目的です。
- 重要要件は「プライバシー重視」「安定動作」「最小運用コスト」です。

## 2. 技術スタック
- 言語: Swift 5.9+
- ビルド/依存管理: Swift Package Manager (`Package.swift`)
- 対応OS: macOS 14+
- UI: SwiftUI（`MenuBarExtra` 含む）
- DB: SQLite + GRDB
- 推論: Ollama HTTP API（`/api/tags`, `/api/generate`）
- テスト: XCTest（`Tests/LogleafTests`）

## 3. コーディングガイドライン
- 変更は必要最小限にし、不要な広域リファクタは行わない。
- レイヤ境界を守る。
  - `Models`: ドメイン型
  - `Repositories`: 永続化アクセス
  - `Services`: 業務ロジック
  - `Infrastructure`: 外部連携・OS連携
  - `ViewModels`: UI状態管理
- エラーは握りつぶさず、原因が追える形で扱う（DB/ファイルI/O/推論通信/キャプチャ）。
- DB変更時はスキーマ・モデル・Repository の整合性を維持する。
- 推論変更時は、プロンプトとJSONパースの堅牢性を優先する。
- ローカル完結要件を壊す外部サービス依存を追加しない。

## 4. プロジェクト構成
- `Sources/Logleaf/`: アプリ起動点（`LogleafApp.swift`）
- `Sources/LogleafLib/`: 主要実装
  - `Database/`: 初期化・マイグレーション
  - `Infrastructure/`: Logger, FileStorage, OllamaClient, PromptBuilder
  - `Models/`: ドメインモデル
  - `Repositories/`: GRDBアクセス
  - `Services/`: Capture/Scheduler/Inference/Aggregation など
  - `ViewModels/`: 画面状態と操作
  - `Views/`: SwiftUI画面
- `Tests/LogleafTests/`: 単体テスト
- `tasks.md`: フェーズ別タスクリスト

## 5. 利用可能リソース
- ビルド: `swift build`
- テスト: `swift test`
- 実行: `swift run Logleaf`
- 参照ドキュメント:
  - `tasks.md`
  - `作業記録アプリ_作業計画書.md`

## 追加運用ルール
- 大きめの変更前に、関連する `Model/Repository/Service` の依存関係を確認する。
- 変更後は可能な限り `swift test` を実行する。未実施なら理由を明記する。
- 回答には、変更ファイル・挙動影響・検証内容・残課題を簡潔に含める。
