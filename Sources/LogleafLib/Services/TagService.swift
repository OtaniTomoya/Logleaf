import Foundation

public final class TagService {
    private let tagRepository: TagRepository

    public init(tagRepository: TagRepository) {
        self.tagRepository = tagRepository
    }

    public func createTag(name: String, colorHex: String? = nil, priority: Int = 0) throws -> Tag {
        let tag = Tag(name: name, colorHex: colorHex, priority: priority)
        try tagRepository.save(tag)
        return tag
    }

    public func updateTag(id: String, name: String? = nil, colorHex: String? = nil,
                   priority: Int? = nil, isActive: Bool? = nil) throws {
        guard var tag = try tagRepository.fetch(id: id) else { return }
        if let name { tag.name = name }
        if let colorHex { tag.colorHex = colorHex }
        if let priority { tag.priority = priority }
        if let isActive { tag.isActive = isActive }
        tag.updatedAt = Date()
        try tagRepository.save(tag)
    }

    public func listActiveTags() throws -> [Tag] {
        try tagRepository.fetchActive()
    }

    public func listAllTags() throws -> [Tag] {
        try tagRepository.fetchAll()
    }

    public func mergeTags(sourceIds: [String], targetId: String) throws {
        try tagRepository.mergeTags(sourceIds: sourceIds, targetId: targetId)
    }

    public func deleteTag(id: String) throws {
        try tagRepository.delete(id: id)
    }
}
