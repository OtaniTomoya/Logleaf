import Foundation

public final class PromptBuilder {
    public init() {}

    public struct BatchInferenceItem {
        public var frontmostApp: String?
        public var frontmostWindowTitle: String?

        public init(frontmostApp: String? = nil, frontmostWindowTitle: String? = nil) {
            self.frontmostApp = frontmostApp
            self.frontmostWindowTitle = frontmostWindowTitle
        }
    }

    public func buildPrompt(input: InferenceInput) -> String {
        let tagEntries = input.allowedTags.map { tag in
            if let desc = tag.tagDescription, !desc.isEmpty {
                return "- \(tag.name): \(desc)"
            } else {
                return "- \(tag.name)"
            }
        }
        let tagList = tagEntries.isEmpty ? "- （タグ未設定）" : tagEntries.joined(separator: "\n")
        let predictedTagsRule = input.allowedTags.isEmpty
            ? "- 現在タグが未設定のため predicted_tags は必ず空配列 [] にしてください"
            : "- predicted_tags は使用可能なタグの中からのみ選んでください"

        var contextInfo = ""
        if let app = input.frontmostApp {
            contextInfo += "前面アプリ: \(app)\n"
        }
        if let title = input.frontmostWindowTitle {
            contextInfo += "ウィンドウタイトル: \(title)\n"
        }

        return """
        あなたは作業分析AIです。スクリーンショットを見て、ユーザーが何の作業をしているか推定してください。

        ## 補助情報
        \(contextInfo)
        ## 使用可能なタグ（この中からのみ選択してください）
        \(tagList)

        ## 出力形式
        以下のJSON形式で出力してください。他のテキストは含めないでください。

        ```json
        {
          "activity_summary": "作業内容の短い説明",
          "predicted_tags": ["タグ1", "タグ2"],
          "reason": "推定理由",
          "sensitivity_flag": "none"
        }
        ```

        ## ルール
        \(predictedTagsRule)
        - sensitivity_flag は none / personal / secret / unknown のいずれかです
        - 判断できない場合は predicted_tags を空配列にしてください
        - 個人情報が含まれる場合は sensitivity_flag を personal にしてください
        """
    }

    public func buildBatchPrompt(items: [BatchInferenceItem], allowedTags: [Tag]) -> String {
        let tagEntries = allowedTags.map { tag in
            if let desc = tag.tagDescription, !desc.isEmpty {
                return "- \(tag.name): \(desc)"
            } else {
                return "- \(tag.name)"
            }
        }
        let tagList = tagEntries.isEmpty ? "- （タグ未設定）" : tagEntries.joined(separator: "\n")
        let predictedTagsRule = allowedTags.isEmpty
            ? "- 現在タグが未設定のため、すべての predicted_tags は必ず空配列 [] にしてください"
            : "- predicted_tags は使用可能なタグの中からのみ選んでください"

        let itemLines = items.enumerated().map { index, item in
            let app = item.frontmostApp ?? "不明"
            let title = item.frontmostWindowTitle ?? "不明"
            return """
            ### ITEM \(index + 1)
            - 前面アプリ: \(app)
            - ウィンドウタイトル: \(title)
            """
        }.joined(separator: "\n\n")

        return """
        あなたは作業分析AIです。与えられた複数のスクリーンショットをそれぞれ独立に分析してください。

        ## 入力件数
        - 全 \(items.count) 件
        - 画像配列の順序と ITEM 番号は一致します（先頭画像が ITEM 1）

        ## 補助情報
        \(itemLines)

        ## 使用可能なタグ（この中からのみ選択してください）
        \(tagList)

        ## 出力形式
        以下の JSON 形式で、必ず `results` 配列に \(items.count) 件すべてを含めてください。他のテキストは含めないでください。

        ```json
        {
          "results": [
            {
              "index": 1,
              "activity_summary": "作業内容の短い説明",
              "predicted_tags": ["タグ1", "タグ2"],
              "reason": "推定理由",
              "sensitivity_flag": "none"
            }
          ]
        }
        ```

        ## ルール
        - `results` の要素数は必ず \(items.count) 件
        - `index` は 1 から \(items.count) までを重複なく1回ずつ使う
        \(predictedTagsRule)
        - sensitivity_flag は none / personal / secret / unknown のいずれかです
        - 判断できない場合は predicted_tags を空配列にしてください
        - 個人情報が含まれる場合は sensitivity_flag を personal にしてください
        """
    }

    public func parseResponse(_ responseText: String, allowedTags: [Tag]) -> InferenceResult? {
        guard let jsonString = extractJSONText(from: responseText) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json else { return nil }
            return parseResultObject(json, allowedTags: allowedTags, fallbackRawJson: jsonString)
        } catch {
            AppLogger.error("Failed to parse inference response: \(error)")
            return nil
        }
    }

    public func parseBatchResponse(
        _ responseText: String,
        expectedCount: Int,
        allowedTags: [Tag]
    ) -> [InferenceResult?]? {
        guard expectedCount > 0 else { return [] }
        guard let jsonString = extractJSONText(from: responseText) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json else { return nil }
            let items = json["results"] as? [[String: Any]] ?? []

            var orderedResults = Array<InferenceResult?>(repeating: nil, count: expectedCount)
            for item in items {
                guard let index = item["index"] as? Int,
                      index >= 1, index <= expectedCount else {
                    continue
                }
                orderedResults[index - 1] = parseResultObject(
                    item,
                    allowedTags: allowedTags,
                    fallbackRawJson: jsonString
                )
            }
            return orderedResults
        } catch {
            AppLogger.error("Failed to parse batch inference response: \(error)")
            return nil
        }
    }

    private func parseResultObject(
        _ json: [String: Any],
        allowedTags: [Tag],
        fallbackRawJson: String
    ) -> InferenceResult {
        let summary = json["activity_summary"] as? String ?? ""
        let tags = json["predicted_tags"] as? [String] ?? []
        let reason = json["reason"] as? String ?? ""
        let sensitivity = json["sensitivity_flag"] as? String ?? "none"
        let allowedTagNames = Set(allowedTags.map { $0.name })
        let filteredTags = tags.filter { allowedTagNames.contains($0) }
        let rawJson = (try? JSONSerialization.data(withJSONObject: json))
            .flatMap { String(data: $0, encoding: .utf8) } ?? fallbackRawJson

        return InferenceResult(
            activitySummary: summary,
            predictedTags: filteredTags,
            reason: reason,
            sensitivityFlag: sensitivity,
            rawJson: rawJson
        )
    }

    private func extractJSONText(from responseText: String) -> String? {
        var jsonString = responseText
        if let range = responseText.range(of: "```json") {
            jsonString = String(responseText[range.upperBound...])
            if let endRange = jsonString.range(of: "```") {
                jsonString = String(jsonString[..<endRange.lowerBound])
            }
        } else if let range = responseText.range(of: "{"),
                  let endRange = responseText.range(of: "}", options: .backwards) {
            jsonString = String(responseText[range.lowerBound...endRange.lowerBound])
        } else {
            return nil
        }

        return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Daily Feedback

    public struct FeedbackInput {
        public var dateString: String
        public var sessions: [(title: String, tags: [String], startTime: String, endTime: String, durationMinutes: Int)]

        public init(dateString: String, sessions: [(title: String, tags: [String], startTime: String, endTime: String, durationMinutes: Int)]) {
            self.dateString = dateString
            self.sessions = sessions
        }
    }

    public func buildFeedbackPrompt(input: FeedbackInput) -> String {
        var sessionList = ""
        for s in input.sessions {
            let tags = s.tags.isEmpty ? "タグなし" : s.tags.joined(separator: ", ")
            sessionList += "- \(s.startTime)〜\(s.endTime)（\(s.durationMinutes)分）: \(s.title) [\(tags)]\n"
        }

        let totalMinutes = input.sessions.reduce(0) { $0 + $1.durationMinutes }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        let totalStr = hours > 0 ? "\(hours)時間\(mins)分" : "\(mins)分"

        return """
        あなたはユーザーの作業記録を分析するアシスタントです。
        以下は \(input.dateString) の作業記録です。

        ## 作業記録（合計: \(totalStr)）
        \(sessionList)

        ## 指示
        上記の作業記録をもとに、以下の内容をまとめてください。

        1. **今日の活動まとめ**: この日にどんな作業をしたか、自然な文章で簡潔にまとめてください。
        2. **良かった点**: 作業の進め方で良いと思われる点があれば触れてください。
        3. **提案・アドバイス**: 作業の傾向から、こんなことにも挑戦してみませんか？という前向きな提案をしてください。新しい学びや改善のヒントなど。

        自然な日本語で、フレンドリーなトーンで書いてください。箇条書きではなく文章で書いてください。
        Markdown は使わないでください。プレーンテキストで出力してください。
        """
    }
}
