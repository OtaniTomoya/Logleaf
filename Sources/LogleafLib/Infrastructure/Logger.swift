import Foundation
import os

public enum AppLogger {
    private static let subsystem = "com.logleaf.app"
    private static let logger = os.Logger(subsystem: subsystem, category: "general")

    public static func debug(_ message: String) {
        logger.debug("\(message)")
    }

    public static func info(_ message: String) {
        logger.info("\(message)")
    }

    public static func warning(_ message: String) {
        logger.warning("\(message)")
    }

    public static func error(_ message: String) {
        logger.error("\(message)")
    }
}
