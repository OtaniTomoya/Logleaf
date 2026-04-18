import Foundation

public final class FileStorageService {
    private let appName = "Logleaf"
    private let fileManager = FileManager.default
    private let appSupportBaseURL: URL

    public var appSupportURL: URL {
        appSupportBaseURL
    }

    public var databaseURL: URL {
        appSupportURL.appendingPathComponent("logleaf.sqlite")
    }

    public var screenshotsBaseURL: URL {
        appSupportURL.appendingPathComponent("screenshots")
    }

    public var logsURL: URL {
        appSupportURL.appendingPathComponent("logs")
    }

    public init(appSupportURL: URL? = nil) {
        if let appSupportURL {
            self.appSupportBaseURL = appSupportURL
        } else {
            let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.appSupportBaseURL = url.appendingPathComponent(appName)
        }
        createDirectories()
    }

    private func createDirectories() {
        let dirs = [appSupportURL, screenshotsBaseURL, logsURL]
        for dir in dirs {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func screenshotDirectory(for date: Date) -> URL {
        let calendar = Calendar.current
        let year = String(format: "%04d", calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let day = String(format: "%02d", calendar.component(.day, from: date))
        let dir = screenshotsBaseURL
            .appendingPathComponent(year)
            .appendingPathComponent(month)
            .appendingPathComponent(day)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func screenshotPath(for date: Date, id: String) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "obs_\(timestamp)_\(id).jpg"
        return screenshotDirectory(for: date).appendingPathComponent(filename)
    }

    public func representativeImagePath(sessionId: String) -> URL {
        screenshotsBaseURL.appendingPathComponent("rep_\(sessionId).jpg")
    }

    public func deleteFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func deleteOldScreenshots(olderThan date: Date) throws {
        let enumerator = fileManager.enumerator(
            at: screenshotsBaseURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jpg" else { continue }
            let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attrs[.creationDate] as? Date,
               creationDate < date {
                try fileManager.removeItem(at: fileURL)
            }
        }
        // Clean up empty directories
        cleanEmptyDirectories(in: screenshotsBaseURL)
    }

    private func cleanEmptyDirectories(in directory: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                cleanEmptyDirectories(in: item)
                let subContents = try? fileManager.contentsOfDirectory(
                    at: item, includingPropertiesForKeys: nil
                )
                if subContents?.isEmpty == true {
                    try? fileManager.removeItem(at: item)
                }
            }
        }
    }
}
