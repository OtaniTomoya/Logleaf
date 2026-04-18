import SwiftUI

@MainActor
public final class TagManagementViewModel: ObservableObject {
    @Published public var tags: [Tag] = []
    @Published public var newTagName: String = ""
    @Published public var newTagColor: String = "#4A90D9"
    @Published public var selectedTagId: String?
    @Published public var errorMessage: String?

    private let tagService: TagService

    public init(tagService: TagService) {
        self.tagService = tagService
        self.newTagColor = tagService.suggestNextColor()
    }

    public func loadTags() {
        do {
            tags = try tagService.listAllTags()
        } catch {
            errorMessage = "タグの読み込みに失敗しました"
        }
    }

    public func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagName = name.isEmpty ? generateDefaultName() : name
        do {
            let tag = try tagService.createTag(name: tagName, colorHex: newTagColor)
            newTagName = ""
            newTagColor = tagService.suggestNextColor()
            loadTags()
            selectedTagId = tag.id
        } catch {
            errorMessage = "タグの追加に失敗しました"
        }
    }

    public func updateTag(_ tag: Tag) {
        do {
            try tagService.saveTag(tag)
            loadTags()
        } catch {
            errorMessage = "タグの更新に失敗しました"
        }
    }

    public func deleteSelectedTag() {
        guard let id = selectedTagId else { return }
        do {
            try tagService.deleteTag(id: id)
            selectedTagId = nil
            loadTags()
        } catch {
            errorMessage = "タグの削除に失敗しました"
        }
    }

    public func deleteTag(at offsets: IndexSet) {
        for index in offsets {
            try? tagService.deleteTag(id: tags[index].id)
        }
        loadTags()
    }

    public func toggleActive(tag: Tag) {
        do {
            try tagService.updateTag(id: tag.id, isActive: !tag.isActive)
            loadTags()
        } catch {
            errorMessage = "タグ状態の変更に失敗しました"
        }
    }

    public func mergeTags(sourceIds: [String], targetId: String) {
        do {
            try tagService.mergeTags(sourceIds: sourceIds, targetId: targetId)
            loadTags()
        } catch {
            errorMessage = "タグの統合に失敗しました"
        }
    }

    private func generateDefaultName() -> String {
        let base = "新しいタグ"
        let existingNames = Set(tags.map(\.name))
        if !existingNames.contains(base) { return base }
        var i = 2
        while existingNames.contains("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }
}
