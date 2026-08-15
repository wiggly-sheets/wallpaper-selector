import Foundation
import AppKit


protocol WallpaperSetting {
    func setWallpaper(_ url: URL, forAllScreens: Bool) throws
}


final class WallpaperProvider: WallpaperSetting {
    func currentWallpaperURL() -> URL? {
        let workspace = NSWorkspace.shared
        guard let screen = NSScreen.main else { return nil }
        return workspace.desktopImageURL(for: screen)
    }

    func setWallpaper(_ url: URL, forAllScreens: Bool) throws {
        let workspace = NSWorkspace.shared
        let screens = NSScreen.screens

        if forAllScreens {
            var lastError: Error?
            for screen in screens {
                do {
                    try workspace.setDesktopImageURL(url, for: screen, options: [:])
                } catch {
                    lastError = error
                    print("[WallpaperProvider] Failed to set wallpaper on screen: \(error)")
                }
            }
            if let lastError {
                throw lastError
            }
        } else {
            guard let screen = NSScreen.main else {
                throw WallpaperProviderError.noMainScreen
            }
            do {
                try workspace.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                throw WallpaperProviderError.failedToSet(error)
            }
        }
    }
}


enum WallpaperProviderError: Error, LocalizedError {
    case noMainScreen
    case failedToSet(Error)

    var errorDescription: String? {
        switch self {
        case .noMainScreen: return "No main screen available."
        case .failedToSet(let underlying): return "Failed to set wallpaper: \(underlying.localizedDescription)"
        }
    }
}


final class MockWallpaperProvider: WallpaperSetting {
    private(set) var calls: [(url: URL, forAllScreens: Bool)] = []
    var throwError: Bool = false
    var errorToThrow: Error?

    func setWallpaper(_ url: URL, forAllScreens: Bool) throws {
        calls.append((url, forAllScreens))
        if throwError {
            throw errorToThrow ?? WallpaperProviderError.failedToSet(NSError(domain: "Mock", code: -1))
        }
    }

    func reset() {
        calls = []
        throwError = false
        errorToThrow = nil
    }
}
