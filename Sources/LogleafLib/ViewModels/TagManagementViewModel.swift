import SwiftUI

@MainActor
public final class TagManagementViewModel: ObservableObject {
    @Published public var tags: [Tag] = []
    @Published public var newTagName: String = ""
    @Published public var newTagColor: String = "#4A90D9"
    @Published public var editingTag: Tag?
    @Published public var errorMessage: String?

    private let tagService: TagService

    public init(tagService: TagService) {
        self.tagService = tagService
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
        guard !name.isEmpty else { return }
        do {
            _ = try tagService.createTag(name: name, colorHex: newTagColor)
            newTagName = ""
            loadTags()
        } catch {
            errorMessage = "タグの追加に失敗しました"
        }
    }

    public func updateTag(_ tag: Tag) {
        do {
            try tagService.updateTag(
                id: tag.id,
                name: tag.name,
                colorHex: tag.colorHex,
                priority: tag.priority,
                isActive: tag.isActive
            )
            loadTags()
        } catch {
            errorMessage = "タグの更新に失敗しました"
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
}
