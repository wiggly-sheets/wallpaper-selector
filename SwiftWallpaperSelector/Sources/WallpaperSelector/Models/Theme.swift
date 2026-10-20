import Foundation

public struct Theme: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var folderPaths: [String]
    public var lightWallpaper: String?
    public var darkWallpaper: String?

    public init(id: String = UUID().uuidString, name: String, folderPaths: [String],
                lightWallpaper: String? = nil, darkWallpaper: String? = nil) {
        self.id = id
        self.name = name
        self.folderPaths = folderPaths
        self.lightWallpaper = lightWallpaper
        self.darkWallpaper = darkWallpaper
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        guard !folderPaths.isEmpty else { return "Untitled Theme" }
        if folderPaths.count <= 2 {
            return folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        }
        return "\((folderPaths[0] as NSString).lastPathComponent) +\(folderPaths.count - 1) more"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, folderPaths, lightWallpaper, darkWallpaper
    }

    /// Decodes leniently: a broken theme must never reject the whole settings file.
    public init(from decoder: Decoder) throws {
        self = Self.decodeObject(from: decoder) ?? Theme(id: "", name: "", folderPaths: [])
    }

    /// Decodes a theme and reports whether the value was an object at all.
    /// A value that is not an object is not a theme, so it is skipped.
    ///
    /// A theme without an id keeps an empty id: the settings file gives it a
    /// stable id, so the same file always produces the same theme ids.
    static func decodeObject(from decoder: Decoder) -> Theme? {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else { return nil }

        let storedID = Self.decode(String.self, .id, in: values) ?? ""
        return Theme(
            id: storedID,
            name: Self.decode(String.self, .name, in: values) ?? "",
            folderPaths: LenientDecoding.stringArray(from: values, forKey: .folderPaths),
            lightWallpaper: Self.decode(String.self, .lightWallpaper, in: values),
            darkWallpaper: Self.decode(String.self, .darkWallpaper, in: values)
        )
    }

    /// Decodes the themes one by one: an element that is not a theme is
    /// skipped, the other themes survive.
    static func decodeArray<T: CodingKey>(
        from container: KeyedDecodingContainer<T>,
        forKey key: T
    ) -> [Theme] {
        let elements = (try? container.decode([ThemeElement].self, forKey: key)) ?? []
        return elements.compactMap(\.theme)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        _ key: CodingKeys,
        in values: KeyedDecodingContainer<CodingKeys>
    ) -> T? {
        let decoded = try? values.decodeIfPresent(type, forKey: key)
        return decoded.flatMap { $0 }
    }
}

/// A theme in an array: an element that is not an object is not a theme.
struct ThemeElement: Decodable {
    let theme: Theme?

    init(from decoder: Decoder) throws {
        theme = Theme.decodeObject(from: decoder)
    }
}
