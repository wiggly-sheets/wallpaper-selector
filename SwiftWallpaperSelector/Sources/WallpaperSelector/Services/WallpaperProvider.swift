import AppKit
import Foundation

@MainActor
protocol WallpaperSetting {
    func setWallpaper(_ url: URL) throws
}

@MainActor
final class WallpaperProvider: WallpaperSetting {
    typealias ApplyToDisplays = (_ url: URL) -> [Result<Void, Error>]
    /// Puts the wallpaper on every Space.
    ///
    /// The seam runs on the main actor, where the wallpaper is applied.
    typealias ApplyToAllSpaces = @MainActor (_ url: URL) -> Void

    private let applyToDisplays: ApplyToDisplays
    /// Puts the wallpaper on every Space.
    ///
    /// The seam is not private, so a test can ask the provider of the app
    /// what it would do without changing the wallpaper of the screen.
    var applyToAllSpaces: ApplyToAllSpaces?

    init(
        applyToDisplays: ApplyToDisplays? = nil,
        applyToAllSpaces: ApplyToAllSpaces? = nil
    ) {
        self.applyToDisplays = applyToDisplays ?? { url in
            let workspace = NSWorkspace.shared
            return NSScreen.screens.map { screen in
                Result {
                    try workspace.setDesktopImageURL(url, for: screen, options: [:])
                }
            }
        }
        self.applyToAllSpaces = applyToAllSpaces
    }

    func setWallpaper(_ url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw WallpaperProviderError.invalidWallpaper(url)
        }

        let results = applyToDisplays(url)
        guard !results.isEmpty else {
            throw WallpaperProviderError.noScreens
        }

        let failures = results.compactMap { result -> Error? in
            guard case .failure(let error) = result else { return nil }
            return error
        }

        if let lastFailure = failures.last {
            throw WallpaperProviderError.failedToSetOnDisplays(
                failedCount: failures.count,
                totalCount: results.count,
                underlying: lastFailure
            )
        }

        // The wallpaper is on every display, so it can go on every Space.
        // A wallpaper that a display refused is not put on every Space: the
        // apply failed, and the caller reports the failure.
        applyToAllSpaces?(url)
    }
}


enum WallpaperProviderError: Error, LocalizedError {
    case invalidWallpaper(URL)
    case noScreens
    case failedToSetOnDisplays(failedCount: Int, totalCount: Int, underlying: Error)

    /// The wallpaper reached at least one display, so it is on the screen
    /// even though another display refused it.
    var didSetOnAtLeastOneDisplay: Bool {
        guard case .failedToSetOnDisplays(let failedCount, let totalCount, _) = self else {
            return false
        }
        return failedCount < totalCount
    }

    var errorDescription: String? {
        switch self {
        case .invalidWallpaper(let url):
            return "Wallpaper does not exist: \(url.path)"
        case .noScreens:
            return "No connected displays are available."
        case .failedToSetOnDisplays(let failedCount, let totalCount, let underlying):
            return "Failed to set wallpaper on \(failedCount) of \(totalCount) displays: \(underlying.localizedDescription)"
        }
    }
}
