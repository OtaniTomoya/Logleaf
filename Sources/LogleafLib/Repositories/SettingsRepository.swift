import Foundation
import GRDB

public final class SettingsRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func get(key: String) throws -> SettingEntry? {
        try databaseManager.reader.read { db in
            try SettingEntry.fetchOne(db, key: key)
        }
    }

    public func save(_ entry: SettingEntry) throws {
        try databaseManager.writer.write { db in
            try entry.save(db)
        }
    }

    public func delete(key: String) throws {
        try databaseManager.writer.write { db in
            _ = try SettingEntry.deleteOne(db, key: key)
        }
    }

    public func getString(forKey key: String) throws -> String? {
        guard let entry = try get(key: key) else { return nil }
        let data = Data(entry.valueJson.utf8)
        return try JSONDecoder().decode(String.self, from: data)
    }

    public func setString(_ value: String, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)!
        try save(SettingEntry(key: key, valueJson: json))
    }

    public func getBool(forKey key: String) throws -> Bool {
        guard let entry = try get(key: key) else { return false }
        let data = Data(entry.valueJson.utf8)
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    public func setBool(_ value: Bool, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)!
        try save(SettingEntry(key: key, valueJson: json))
    }

    public func getInt(forKey key: String) throws -> Int? {
        guard let entry = try get(key: key) else { return nil }
        let data = Data(entry.valueJson.utf8)
        return try JSONDecoder().decode(Int.self, from: data)
    }

    public func setInt(_ value: Int, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)!
        try save(SettingEntry(key: key, valueJson: json))
    }
}
