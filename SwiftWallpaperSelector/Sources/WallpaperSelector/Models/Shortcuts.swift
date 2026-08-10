import Foundation

/// User-configurable global keyboard shortcuts.
public struct Shortcuts: Codable, Equatable {
    public var showMain: String?
    public var showPreview: String?
    public var showMenu: String?

    public init(showMain: String? = nil, showPreview: String? = nil, showMenu: String? = nil) {
        self.showMain = showMain
        self.showPreview = showPreview
        self.showMenu = showMenu
    }

    public static let `default` = Shortcuts()
}
