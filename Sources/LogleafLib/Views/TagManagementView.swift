import SwiftUI
import AppKit

public struct TagManagementView: View {
    @StateObject var viewModel: TagManagementViewModel

    public init(viewModel: TagManagementViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 20) {
            tagListSection
                .frame(minWidth: 240, maxWidth: 320)

            tagDetailSection

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .onAppear { viewModel.loadTags() }
    }

    // MARK: - Tag List (macOS style bordered list with +/- buttons)

    private var tagListSection: some View {
        VStack(spacing: 0) {
            // Bordered tag list
            Group {
                if viewModel.tags.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("タグがありません")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List(selection: $viewModel.selectedTagId) {
                        ForEach(viewModel.tags) { tag in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex ?? "#4A90D9"))
                                    .frame(width: 10, height: 10)

                                Text(tag.name)
                                    .lineLimit(1)

                                Spacer()

                                if !tag.isActive {
                                    Text("無効")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                            }
                            .tag(tag.id)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(minHeight: 120, maxHeight: 240)
                }
            }

            // +/- toolbar at the bottom of the list
            HStack(spacing: 0) {
                Button(action: { viewModel.addTag() }) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)

                Divider()
                    .frame(height: 16)

                Button(action: { viewModel.deleteSelectedTag() }) {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedTagId == nil)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Tag Detail Editor

    @ViewBuilder
    private var tagDetailSection: some View {
        if let selectedId = viewModel.selectedTagId,
           let tagIndex = viewModel.tags.firstIndex(where: { $0.id == selectedId }) {
            let tag = viewModel.tags[tagIndex]
            TagDetailEditor(tag: tag) { updatedTag in
                viewModel.updateTag(updatedTag)
            }
        }
    }
}

// MARK: - Tag Detail Editor

private struct TagDetailEditor: View {
    let tag: Tag
    let onUpdate: (Tag) -> Void

    @State private var editName: String = ""
    @State private var editDescription: String = ""
    @State private var editColor: Color = .blue
    @State private var editIsActive: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                // Name
                LabeledContent("名前") {
                    TextField("タグ名", text: $editName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit { saveChanges() }
                        .onChange(of: editName) {
                            guard editName != tag.name else { return }
                            saveChanges()
                        }
                }

                // Description
                LabeledContent("説明") {
                    TextField("推論時のヒントになる説明", text: $editDescription)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit { saveChanges() }
                        .onChange(of: editDescription) {
                            guard editDescription != (tag.tagDescription ?? "") else { return }
                            saveChanges()
                        }
                }

                // Color
                LabeledContent("カラー") {
                    ColorPicker("", selection: $editColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: editColor) { saveChanges() }
                }

                // Active toggle
                LabeledContent("有効") {
                    Toggle("", isOn: $editIsActive)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: editIsActive) { saveChanges() }
                }
        }
        .onAppear { loadTagValues() }
        .onChange(of: tag.id) { loadTagValues() }
    }

    private func loadTagValues() {
        editName = tag.name
        editDescription = tag.tagDescription ?? ""
        editColor = Color(hex: tag.colorHex ?? "#4A90D9")
        editIsActive = tag.isActive
    }

    private func saveChanges() {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var updated = tag
        updated.name = name
        updated.tagDescription = editDescription.isEmpty ? nil : editDescription
        updated.colorHex = editColor.toHex()
        updated.isActive = editIsActive
        onUpdate(updated)
    }
}

// MARK: - Color Extension

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else {
            return "#4A90D9"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
