import SwiftUI

@MainActor
public final class ExclusionRuleViewModel: ObservableObject {
    @Published public var rules: [ExclusionRule] = []
    @Published public var newRuleType: ExclusionRule.RuleType = .app
    @Published public var newRuleValue: String = ""
    @Published public var errorMessage: String?

    private let exclusionService: ExclusionService

    public init(exclusionService: ExclusionService) {
        self.exclusionService = exclusionService
    }

    public func loadRules() {
        do {
            rules = try exclusionService.listRules()
        } catch {
            errorMessage = "除外ルールの読み込みに失敗しました"
        }
    }

    public func addRule() {
        let value = newRuleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let rule = ExclusionRule(ruleType: newRuleType, value: value)
        do {
            try exclusionService.saveRule(rule)
            newRuleValue = ""
            loadRules()
        } catch {
            errorMessage = "ルールの追加に失敗しました"
        }
    }

    public func deleteRule(at offsets: IndexSet) {
        for index in offsets {
            try? exclusionService.deleteRule(id: rules[index].id)
        }
        loadRules()
    }

    public func toggleRule(_ rule: ExclusionRule) {
        var updated = rule
        updated.isActive.toggle()
        updated.updatedAt = Date()
        do {
            try exclusionService.saveRule(updated)
            loadRules()
        } catch {
            errorMessage = "ルールの更新に失敗しました"
        }
    }

    public func addCurrentFrontmostApp(context: FrontmostContext) {
        guard let bundleId = context.bundleId else { return }
        let rule = ExclusionRule(ruleType: .app, value: bundleId)
        do {
            try exclusionService.saveRule(rule)
            loadRules()
        } catch {
            errorMessage = "除外の追加に失敗しました"
        }
    }
}
