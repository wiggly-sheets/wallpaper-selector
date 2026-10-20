import Foundation

public struct Shortcuts: Codable, Equatable, Sendable {
    public var showMain: String?
    public var showPreview: String?
    public var showMenu: String?

    public init(showMain: String? = nil, showPreview: String? = nil, showMenu: String? = nil) {
        self.showMain = showMain
        self.showPreview = showPreview
        self.showMenu = showMenu
    }

    public static let `default` = Shortcuts()

    private enum CodingKeys: String, CodingKey {
        case showMain, showPreview, showMenu
    }

    /// Decodes leniently: one wrong-typed shortcut must never wipe the others.
    public init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            showMain = nil
            showPreview = nil
            showMenu = nil
            return
        }

        func decode(_ key: CodingKeys) -> String? {
            let decoded = try? values.decodeIfPresent(String.self, forKey: key)
            return decoded.flatMap { $0 }
        }

        showMain = decode(.showMain)
        showPreview = decode(.showPreview)
        showMenu = decode(.showMenu)
    }
}
