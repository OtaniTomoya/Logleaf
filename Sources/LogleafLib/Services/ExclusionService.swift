import Foundation

public final class ExclusionService {
    private let repository: ExclusionRuleRepository

    public init(repository: ExclusionRuleRepository) {
        self.repository = repository
    }

    public func shouldExclude(context: FrontmostContext) -> Bool {
        guard let rules = try? repository.fetchActive() else { return false }

        for rule in rules {
            switch rule.ruleType {
            case .app:
                if let bundleId = context.bundleId, bundleId == rule.value {
                    return true
                }
                if let appName = context.appName, appName == rule.value {
                    return true
                }
            case .windowTitle:
                if let title = context.windowTitle, title.contains(rule.value) {
                    return true
                }
            case .timeRange:
                if isCurrentTimeInRange(rule.value) {
                    return true
                }
            case .manual:
                // Manual exclusion handled elsewhere
                break
            }
        }
        return false
    }

    public func listRules() throws -> [ExclusionRule] {
        try repository.fetchAll()
    }

    public func saveRule(_ rule: ExclusionRule) throws {
        try repository.save(rule)
    }

    public func deleteRule(id: String) throws {
        try repository.delete(id: id)
    }

    private func isCurrentTimeInRange(_ rangeString: String) -> Bool {
        // Format: "HH:mm-HH:mm" (e.g., "22:00-06:00")
        let parts = rangeString.split(separator: "-")
        guard parts.count == 2 else { return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let now = formatter.string(from: Date())

        let start = String(parts[0])
        let end = String(parts[1])

        if start <= end {
            return now >= start && now <= end
        } else {
            // Overnight range (e.g., 22:00-06:00)
            return now >= start || now <= end
        }
    }
}
