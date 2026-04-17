import SwiftUI

public struct TagManagementView: View {
    @StateObject var viewModel: TagManagementViewModel

    public init(viewModel: TagManagementViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Add tag
            HStack {
                ColorPicker("", selection: colorBinding)
                    .frame(width: 30)
                TextField("新しいタグ名", text: $viewModel.newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.addTag() }
                Button("追加") { viewModel.addTag() }
                    .disabled(viewModel.newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            if viewModel.tags.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("タグがありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.tags) { tag in
                        HStack {
                            Circle()
                                .fill(Color(hex: tag.colorHex ?? "#4A90D9"))
                                .frame(width: 12, height: 12)

                            Text(tag.name)
                                .fontWeight(.medium)

                            Spacer()

                            Text("優先度: \(tag.priority)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Toggle("", isOn: Binding(
                                get: { tag.isActive },
                                set: { _ in viewModel.toggleActive(tag: tag) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: viewModel.deleteTag)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
        .onAppear { viewModel.loadTags() }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.newTagColor) },
            set: { newColor in
                // Convert Color to hex
                if let components = NSColor(newColor).cgColor.components, components.count >= 3 {
                    let r = Int(components[0] * 255)
                    let g = Int(components[1] * 255)
                    let b = Int(components[2] * 255)
                    viewModel.newTagColor = String(format: "#%02X%02X%02X", r, g, b)
                }
            }
        )
    }
}
