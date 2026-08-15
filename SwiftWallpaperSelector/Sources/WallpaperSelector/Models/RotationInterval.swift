import Foundation

public enum RotationInterval: Int, Codable, Equatable, CaseIterable {
    case off = 0
    case minutes30 = 30
    case hour1 = 60
    case hours12 = 720
    case daily = 1440

    public var label: String {
        switch self {
        case .off: return "Off"
        case .minutes30: return "30 min"
        case .hour1: return "1 hr"
        case .hours12: return "12 hr"
        case .daily: return "Daily"
        }
    }
}
