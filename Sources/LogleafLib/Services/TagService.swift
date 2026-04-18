import Foundation

public final class TagService {
    private let tagRepository: TagRepository

    /// Distinct color palette for automatic tag color assignment
    private static let defaultColors = [
        "#E74C3C", // red
        "#3498DB", // blue
        "#2ECC71", // green
        "#F39C12", // orange
        "#9B59B6", // purple
        "#1ABC9C", // teal
        "#E67E22", // dark orange
        "#E91E63", // pink
        "#00BCD4", // cyan
        "#8BC34A", // light green
        "#FF5722", // deep orange
        "#607D8B", // blue grey
        "#795548", // brown
        "#CDDC39", // lime
        "#FF9800", // amber
    ]

    public init(tagRepository: TagRepository) {
        self.tagRepository = tagRepository
    }

    public func createTag(name: String, colorHex: String? = nil, tagDescription: String? = nil) throws -> Tag {
        let resolvedColor = colorHex ?? nextDistinguishableColor()
        let tag = Tag(name: name, colorHex: resolvedColor, tagDescription: tagDescription)
        try tagRepository.save(tag)
        return tag
    }

    /// 既存タグと視覚的に区別しやすい色を提案する
    public func suggestNextColor() -> String {
        nextDistinguishableColor()
    }

    public func saveTag(_ tag: Tag) throws {
        var updated = tag
        updated.updatedAt = Date()
        try tagRepository.save(updated)
    }

    public func updateTag(id: String, name: String? = nil, colorHex: String? = nil,
                   tagDescription: String? = nil, isActive: Bool? = nil) throws {
        guard var tag = try tagRepository.fetch(id: id) else { return }
        if let name { tag.name = name }
        if let colorHex { tag.colorHex = colorHex }
        if let tagDescription { tag.tagDescription = tagDescription }
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

    /// 既存タグと視覚的に区別しやすい色をランダムに選択する
    private func nextDistinguishableColor() -> String {
        let existing = (try? tagRepository.fetchAll().compactMap(\.colorHex)) ?? []
        let usedSet = Set(existing.map { $0.uppercased() })

        // パレットから未使用色を収集し、ランダムに1つ返す
        let unused = Self.defaultColors.filter { !usedSet.contains($0.uppercased()) }
        if let picked = unused.randomElement() {
            return picked
        }

        // 全色使用済み → 既存色とHSL距離が最大になる色を生成
        return generateDistinguishableColor(existing: existing)
    }

    /// 既存色から最も離れた色相の色をランダム生成する
    private func generateDistinguishableColor(existing: [String]) -> String {
        let existingHues = existing.compactMap { Self.hueFromHex($0) }

        guard !existingHues.isEmpty else {
            return Self.defaultColors.randomElement() ?? "#4A90D9"
        }

        // 色相環上で既存色から最も離れた隙間を見つける
        let sorted = existingHues.sorted()
        var bestGap: Double = 0
        var bestMid: Double = 0

        for i in 0..<sorted.count {
            let next = (i + 1 < sorted.count) ? sorted[i + 1] : sorted[0] + 360
            let gap = next - sorted[i]
            if gap > bestGap {
                bestGap = gap
                bestMid = sorted[i] + gap / 2
            }
        }

        // 隙間の中心付近にランダムな揺らぎを加える
        let jitter = Double.random(in: -bestGap * 0.15...bestGap * 0.15)
        let hue = (bestMid + jitter).truncatingRemainder(dividingBy: 360)
        let finalHue = hue < 0 ? hue + 360 : hue

        let saturation = Double.random(in: 0.55...0.85)
        let lightness = Double.random(in: 0.45...0.60)

        return Self.hexFromHSL(h: finalHue, s: saturation, l: lightness)
    }

    // MARK: - Color Space Helpers

    private static func hueFromHex(_ hex: String) -> Double? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let val = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        guard delta > 0.01 else { return 0 } // 無彩色

        var hue: Double
        if maxC == r {
            hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == g {
            hue = 60 * (((b - r) / delta) + 2)
        } else {
            hue = 60 * (((r - g) / delta) + 4)
        }
        if hue < 0 { hue += 360 }
        return hue
    }

    private static func hexFromHSL(h: Double, s: Double, l: Double) -> String {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }

        let ri = Int((r1 + m) * 255)
        let gi = Int((g1 + m) * 255)
        let bi = Int((b1 + m) * 255)
        return String(format: "#%02X%02X%02X", min(ri, 255), min(gi, 255), min(bi, 255))
    }
}
