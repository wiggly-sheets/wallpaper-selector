import Foundation

public enum RotationAction: String, Codable, Equatable, CaseIterable {
    case shuffle = "shuffle"
    case next = "next"
    case previous = "previous"
    case themeShuffle = "themeShuffle"
    case themeNext = "themeNext"
    case themePrevious = "themePrevious"

    public var label: String {
        switch self {
        case .shuffle: return "Shuffle Wallpaper"
        case .next: return "Next Wallpaper"
        case .previous: return "Previous Wallpaper"
        case .themeShuffle: return "Shuffle Theme"
        case .themeNext: return "Next Theme"
        case .themePrevious: return "Previous Theme"
        }
    }
}
