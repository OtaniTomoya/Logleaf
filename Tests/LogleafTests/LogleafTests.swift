import XCTest
@testable import LogleafLib

final class LogleafTests: XCTestCase {

    func testAppSettingsDefaultOllamaModel() {
        let settings = AppSettings()
        XCTAssertEqual(settings.ollamaModel, "gemma4:e4b")
    }

    // MARK: - Tag Tests

    func testTagCreation() {
        let tag = Tag(name: "テスト", colorHex: "#FF0000", tagDescription: "テスト用タグ")
        XCTAssertEqual(tag.name, "テスト")
        XCTAssertEqual(tag.colorHex, "#FF0000")
        XCTAssertEqual(tag.tagDescription, "テスト用タグ")
        XCTAssertTrue(tag.isActive)
    }

    // MARK: - ExclusionRule Tests

    func testExclusionRuleTypes() {
        let appRule = ExclusionRule(ruleType: .app, value: "com.apple.Safari")
        XCTAssertEqual(appRule.ruleType, .app)

        let titleRule = ExclusionRule(ruleType: .windowTitle, value: "パスワード")
        XCTAssertEqual(titleRule.ruleType, .windowTitle)

        let timeRule = ExclusionRule(ruleType: .timeRange, value: "22:00-06:00")
        XCTAssertEqual(timeRule.ruleType, .timeRange)
    }

    // MARK: - WorkSession Tests

    func testWorkSessionDuration() {
        let start = Date()
        let end = start.addingTimeInterval(300) // 5 minutes
        let session = WorkSession(startAt: start, endAt: end)
        XCTAssertEqual(session.durationMinutes, 5)
    }

    func testWorkSessionDisplayTitle() {
        let session1 = WorkSession(startAt: Date(), endAt: Date(), aiTitle: "AI Title")
        XCTAssertEqual(session1.displayTitle, "AI Title")

        let session2 = WorkSession(startAt: Date(), endAt: Date(), aiTitle: "AI", finalTitle: "User")
        XCTAssertEqual(session2.displayTitle, "User")

        let session3 = WorkSession(startAt: Date(), endAt: Date())
        XCTAssertEqual(session3.displayTitle, "未分類")
    }

    // MARK: - PromptBuilder Tests

    func testPromptBuildContainsAllowedTags() {
        let builder = PromptBuilder()
        let tags = [
            Tag(name: "開発"),
            Tag(name: "メール"),
            Tag(name: "会議")
        ]
        let input = InferenceInput(
            imageURL: URL(fileURLWithPath: "/tmp/test.jpg"),
            frontmostApp: "Xcode",
            frontmostWindowTitle: "MyProject",
            allowedTags: tags
        )
        let prompt = builder.buildPrompt(input: input)
        XCTAssertTrue(prompt.contains("開発"))
        XCTAssertTrue(prompt.contains("メール"))
        XCTAssertTrue(prompt.contains("会議"))
        XCTAssertTrue(prompt.contains("Xcode"))
    }

    func testParseValidResponse() {
        let builder = PromptBuilder()
        let tags = [Tag(name: "開発"), Tag(name: "メール")]
        let json = """
        {
          "activity_summary": "コードを書いている",
          "predicted_tags": ["開発"],
          "reason": "IDEが見えるため",
          "sensitivity_flag": "none"
        }
        """
        let result = builder.parseResponse(json, allowedTags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.activitySummary, "コードを書いている")
        XCTAssertEqual(result?.predictedTags, ["開発"])
    }

    func testParseResponseFiltersInvalidTags() {
        let builder = PromptBuilder()
        let tags = [Tag(name: "開発")]
        let json = """
        {
          "activity_summary": "作業中",
          "predicted_tags": ["開発", "存在しないタグ"],
          "reason": "test",
          "sensitivity_flag": "none"
        }
        """
        let result = builder.parseResponse(json, allowedTags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.predictedTags, ["開発"])
    }

    func testParseResponseHandlesMissingFields() {
        let builder = PromptBuilder()
        let tags = [Tag(name: "テスト")]
        let json = """
        {
          "activity_summary": "テスト",
          "predicted_tags": ["テスト"],
          "reason": "test",
          "sensitivity_flag": "none"
        }
        """
        let result = builder.parseResponse(json, allowedTags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.predictedTags, ["テスト"])
    }

    func testParseInvalidJSON() {
        let builder = PromptBuilder()
        let result = builder.parseResponse("not json", allowedTags: [])
        XCTAssertNil(result)
    }

    func testParseMarkdownWrappedJSON() {
        let builder = PromptBuilder()
        let tags = [Tag(name: "開発")]
        let response = """
        ```json
        {
          "activity_summary": "開発中",
          "predicted_tags": ["開発"],
          "reason": "IDE visible",
          "sensitivity_flag": "none"
        }
        ```
        """
        let result = builder.parseResponse(response, allowedTags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.activitySummary, "開発中")
    }

    func testParseValidBatchResponse() {
        let builder = PromptBuilder()
        let tags = [Tag(name: "開発"), Tag(name: "会議")]
        let json = """
        {
          "results": [
            {
              "index": 1,
              "activity_summary": "実装中",
              "predicted_tags": ["開発"],
              "reason": "IDE が表示されている",
              "sensitivity_flag": "none"
            },
            {
              "index": 2,
              "activity_summary": "打ち合わせ",
              "predicted_tags": ["会議"],
              "reason": "通話画面",
              "sensitivity_flag": "none"
            }
          ]
        }
        """
        let results = builder.parseBatchResponse(json, expectedCount: 2, allowedTags: tags)
        guard let parsed = results else {
            XCTFail("バッチ結果の解析に失敗")
            return
        }
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0]?.activitySummary, "実装中")
        XCTAssertEqual(parsed[1]?.predictedTags, ["会議"])
    }

    func testParseBatchResponseFiltersInvalidTags() {
        let builder = PromptBuilder()
        let tags = [Tag(name: "開発")]
        let json = """
        {
          "results": [
            {
              "index": 1,
              "activity_summary": "作業中",
              "predicted_tags": ["開発", "未知タグ"],
              "reason": "test",
              "sensitivity_flag": "none"
            }
          ]
        }
        """
        let results = builder.parseBatchResponse(json, expectedCount: 1, allowedTags: tags)
        guard let parsed = results else {
            XCTFail("バッチ結果の解析に失敗")
            return
        }
        XCTAssertEqual(parsed[0]?.predictedTags, ["開発"])
    }

    // MARK: - CaptureJob Tests

    func testCaptureJobStatus() {
        var job = CaptureJob(status: .queued)
        XCTAssertEqual(job.status, .queued)
        job.status = .succeeded
        XCTAssertEqual(job.status, .succeeded)
    }

    // MARK: - OllamaClient Tests

    func testOllamaClientInvalidHostThrowsInsteadOfCrashing() async {
        let client = OllamaClient()
        client.configure(host: "localhost:11434 bad host", model: "llava")

        do {
            _ = try await client.testConnection()
            XCTFail("無効ホストではエラーになるべき")
        } catch let error as OllamaError {
            switch error {
            case .connectionFailed:
                break
            default:
                XCTFail("connectionFailed 以外のエラー: \(error)")
            }
        } catch {
            XCTFail("想定外のエラー型: \(error)")
        }
    }
}
