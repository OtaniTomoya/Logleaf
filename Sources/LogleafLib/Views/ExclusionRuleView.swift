import SwiftUI

public struct ExclusionRuleView: View {
    @StateObject var viewModel: ExclusionRuleViewModel

    public init(viewModel: ExclusionRuleViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Add rule
            HStack {
                Picker("種別", selection: $viewModel.newRuleType) {
                    ForEach(ExclusionRule.RuleType.allCases, id: \.self) { type in
                        Text(ruleTypeLabel(type)).tag(type)
                    }
                }
                .frame(width: 150)

                TextField(rulePlaceholder, text: $viewModel.newRuleValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.addRule() }

                Button("追加") { viewModel.addRule() }
                    .disabled(viewModel.newRuleValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            if viewModel.rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("除外ルールがありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.rules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.value)
                                    .fontWeight(.medium)
                                Text(ruleTypeLabel(rule.ruleType))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { rule.isActive },
                                set: { _ in viewModel.toggleRule(rule) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: viewModel.deleteRule)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
        .onAppear { viewModel.loadRules() }
    }

    private func ruleTypeLabel(_ type: ExclusionRule.RuleType) -> String {
        switch type {
        case .app: return "アプリ"
        case .windowTitle: return "ウィンドウタイトル"
        case .timeRange: return "時間帯"
        case .manual: return "手動"
        }
    }

    private var rulePlaceholder: String {
        switch viewModel.newRuleType {
        case .app: return "バンドルIDまたはアプリ名"
        case .windowTitle: return "タイトルに含まれる文字列"
        case .timeRange: return "HH:mm-HH:mm (例: 22:00-06:00)"
        case .manual: return "メモ"
        }
    }
}
