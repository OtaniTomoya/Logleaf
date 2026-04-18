import Foundation

public protocol OllamaClientProtocol: AnyObject {
    var configuredHost: String { get }
    var configuredModel: String { get }
    func configure(host: String, model: String)
    func testConnection() async throws -> Bool
    func listModels() async throws -> [String]
    func generate(prompt: String, imageBase64: String) async throws -> String
    func generate(prompt: String, imageBase64List: [String]) async throws -> String
    func generateText(prompt: String) async throws -> String
}

public final class OllamaClient {
    private let session = URLSession.shared
    private var baseURL: String = "http://localhost:11434"
    private var model: String = "gemma4:e4b"

    public var configuredHost: String { baseURL }
    public var configuredModel: String { model }

    public init() {}

    public func configure(host: String, model: String) {
        self.baseURL = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
    }

    public func testConnection() async throws -> Bool {
        let url = try endpointURL(path: "/api/tags")
        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    public func listModels() async throws -> [String] {
        let url = try endpointURL(path: "/api/tags")
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []
        return models.compactMap { $0["name"] as? String }
    }

    public func generate(prompt: String, imageBase64: String) async throws -> String {
        return try await performGeneration(prompt: prompt, images: [imageBase64])
    }

    public func generate(prompt: String, imageBase64List: [String]) async throws -> String {
        return try await performGeneration(prompt: prompt, images: imageBase64List)
    }

    public func generateText(prompt: String) async throws -> String {
        return try await performGeneration(prompt: prompt, images: nil)
    }

    private func performGeneration(prompt: String, images: [String]?) async throws -> String {
        let url = try endpointURL(path: "/api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "keep_alive": "0s",
            "options": [
                "temperature": 0.1,
                "num_predict": 512
            ]
        ]
        if let images {
            body["images"] = images
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw classifyRequestError(from: data)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responseText = json?["response"] as? String else {
            throw OllamaError.invalidResponse
        }

        return responseText
    }

    private func endpointURL(path: String) throws -> URL {
        let normalizedBaseURL: String
        if baseURL.hasPrefix("http://") || baseURL.hasPrefix("https://") {
            normalizedBaseURL = baseURL
        } else {
            normalizedBaseURL = "http://\(baseURL)"
        }

        guard var components = URLComponents(string: normalizedBaseURL),
              components.host != nil else {
            throw OllamaError.connectionFailed
        }
        components.path = path

        guard let url = components.url else {
            throw OllamaError.connectionFailed
        }
        return url
    }

    private func classifyRequestError(from data: Data) -> OllamaError {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = (json["error"] as? String)?.lowercased(),
           errorMessage.contains("model"),
           errorMessage.contains("not found") {
            return .modelNotFound
        }

        if let rawText = String(data: data, encoding: .utf8)?.lowercased(),
           rawText.contains("model"),
           rawText.contains("not found") {
            return .modelNotFound
        }

        return .requestFailed
    }
}

extension OllamaClient: OllamaClientProtocol {}

public enum OllamaError: Error, LocalizedError {
    case connectionFailed
    case requestFailed
    case invalidResponse
    case modelNotFound

    public var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Ollamaに接続できません"
        case .requestFailed: return "推論リクエストが失敗しました"
        case .invalidResponse: return "無効なレスポンスです"
        case .modelNotFound: return "モデルが見つかりません"
        }
    }
}
