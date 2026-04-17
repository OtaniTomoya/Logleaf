import Foundation

public final class PromptBuilder {
    public init() {}

    public func buildPrompt(input: InferenceInput) -> String {
        let tagNames = input.allowedTags.map { $0.name }
        let tagList = tagNames.joined(separator: ", ")

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
          "confidence": 0.85,
          "reason": "推定理由",
          "sensitivity_flag": "none"
        }
        ```

        ## ルール
        - predicted_tags は使用可能なタグの中からのみ選んでください
        - confidence は 0.0 から 1.0 の範囲で設定してください
        - sensitivity_flag は none / personal / secret / unknown のいずれかです
        - 判断できない場合は predicted_tags を空配列に、confidence を 0.0 にしてください
        - 個人情報が含まれる場合は sensitivity_flag を personal にしてください
        """
    }

    public func parseResponse(_ responseText: String, allowedTags: [Tag]) -> InferenceResult? {
        // Extract JSON from response (may be wrapped in markdown code block)
        var jsonString = responseText
        if let range = responseText.range(of: "```json") {
            jsonString = String(responseText[range.upperBound...])
            if let endRange = jsonString.range(of: "```") {
                jsonString = String(jsonString[..<endRange.lowerBound])
            }
        } else if let range = responseText.range(of: "{"),
                  let endRange = responseText.range(of: "}", options: .backwards) {
            jsonString = String(responseText[range.lowerBound...endRange.lowerBound])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json else { return nil }

            let summary = json["activity_summary"] as? String ?? ""
            let tags = json["predicted_tags"] as? [String] ?? []
            let confidence = json["confidence"] as? Double ?? 0.0
            let reason = json["reason"] as? String ?? ""
            let sensitivity = json["sensitivity_flag"] as? String ?? "none"

            // Filter to allowed tags only
            let allowedTagNames = Set(allowedTags.map { $0.name })
            let filteredTags = tags.filter { allowedTagNames.contains($0) }

            // Validate confidence range
            let clampedConfidence = min(max(confidence, 0.0), 1.0)

            return InferenceResult(
                activitySummary: summary,
                predictedTags: filteredTags,
                confidence: clampedConfidence,
                reason: reason,
                sensitivityFlag: sensitivity,
                rawJson: jsonString
            )
        } catch {
            AppLogger.error("Failed to parse inference response: \(error)")
            return nil
        }
    }
}
