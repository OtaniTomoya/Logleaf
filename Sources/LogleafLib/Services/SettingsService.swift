import Foundation

public final class SettingsService {
    private let repository: SettingsRepository

    public init(repository: SettingsRepository) {
        self.repository = repository
    }

    public func loadSettings() throws -> AppSettings {
        var settings = AppSettings()
        if let interval = try repository.getInt(forKey: "capture_interval_seconds") {
            settings.captureIntervalSeconds = interval
        }
        if let cpInterval = try repository.getInt(forKey: "checkpoint_interval_minutes") {
            settings.checkpointIntervalMinutes = cpInterval
        }
        if let host = try repository.getString(forKey: "ollama_host") {
            settings.ollamaHost = host
        }
        if let model = try repository.getString(forKey: "ollama_model") {
            settings.ollamaModel = model
        }
        if let days = try repository.getInt(forKey: "retention_days") {
            settings.retentionDays = days
        }
        if try repository.get(key: "auto_delete_enabled") != nil {
            settings.autoDeleteEnabled = try repository.getBool(forKey: "auto_delete_enabled")
        }
        return settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try repository.setInt(settings.captureIntervalSeconds, forKey: "capture_interval_seconds")
        try repository.setInt(settings.checkpointIntervalMinutes, forKey: "checkpoint_interval_minutes")
        try repository.setString(settings.ollamaHost, forKey: "ollama_host")
        try repository.setString(settings.ollamaModel, forKey: "ollama_model")
        try repository.setInt(settings.retentionDays, forKey: "retention_days")
        try repository.setBool(settings.autoDeleteEnabled, forKey: "auto_delete_enabled")
    }

    public func loadBool(forKey key: String) throws -> Bool {
        try repository.getBool(forKey: key)
    }

    public func saveBool(_ value: Bool, forKey key: String) throws {
        try repository.setBool(value, forKey: key)
    }

    public func loadString(forKey key: String) throws -> String? {
        try repository.getString(forKey: key)
    }

    public func saveString(_ value: String, forKey key: String) throws {
        try repository.setString(value, forKey: key)
    }
}
