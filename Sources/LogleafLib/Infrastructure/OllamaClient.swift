import Foundation

public final class OllamaClient {
    private let session = URLSession.shared
    private var baseURL: String = "http://localhost:11434"
    private var model: String = "llava"

    var configuredHost: String { baseURL }
    var configuredModel: String { model }

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
        let url = try endpointURL(path: "/api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "images": [imageBase64],
            "stream": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 512
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
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
}

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
