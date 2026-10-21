import Foundation

enum AllSpacesApplierError: Error, LocalizedError, Equatable {
    case wallpaperNotFound(path: String)
    case storeNotFound(path: String)
    case backupFailed(path: String, reason: String)
    case verificationFailed(attempts: Int)
    case storeFailure(reason: String)

    var errorDescription: String? {
        switch self {
        case .wallpaperNotFound(let path):
            return "The wallpaper file is missing: \(path)"
        case .storeNotFound:
            return "This feature needs macOS 14 or newer, because this Mac has no wallpaper store."
        case .backupFailed(let path, let reason):
            return "The wallpaper store could not be backed up to \(path): \(reason)"
        case .verificationFailed(let attempts):
            return "The wallpaper store did not keep the wallpaper after \(attempts) tries."
        case .storeFailure(let reason):
            return reason
        }
    }
}

/// Puts the wallpaper on every Space.
///
/// The wallpaper agent keeps the wallpaper of every Space and Display in its
/// store file. The app writes that file and restarts the agent, so the
/// wallpaper reaches every Space.
@MainActor
final class AllSpacesApplier {

    /// The backup of the store, taken once before the first write.
    ///
    /// The backup lives in the folder of the app, not next to the store.
    nonisolated static var defaultBackupURL: URL {
        SettingsManager.defaultSettingsDirectory
            .appendingPathComponent("WallpaperIndex.plist.backup", isDirectory: false)
    }

    /// Reports that the wallpaper could not be put on every Space.
    var onError: ((String) -> Void)?

    /// Reports that the wallpaper is on every Space.
    var onApplied: (() -> Void)?

    private let store: WallpaperStore
    private let storeURL: URL
    private let backupURL: URL
    private let restartAgent: () -> Void

    /// The number of times the store is written before the apply is given up.
    ///
    /// shortcut: the agent can write the store from its own memory between
    /// the write and the restart, so the wallpaper is written again. Three
    /// tries are enough in practice; the apply fails when the agent keeps
    /// overwriting the store.
    private static let maximumAttempts = 3

    init(
        storeURL: URL = WallpaperStore.defaultStoreURL,
        backupURL: URL = AllSpacesApplier.defaultBackupURL,
        restartAgent: @escaping () -> Void = AllSpacesApplier.restartWallpaperAgent
    ) {
        self.store = WallpaperStore()
        self.storeURL = storeURL
        self.backupURL = backupURL
        self.restartAgent = restartAgent
    }

    /// Puts the wallpaper on every Space.
    ///
    /// The failure is reported through `onError`, the success through
    /// `onApplied`.
    func apply(_ imageURL: URL) {
        do {
            try applyWallpaper(imageURL)
            onApplied?()
        } catch {
            onError?(Self.message(for: error, imageURL: imageURL))
        }
    }

    private func applyWallpaper(_ imageURL: URL) throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw AllSpacesApplierError.wallpaperNotFound(path: imageURL.path)
        }
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw AllSpacesApplierError.storeNotFound(path: storeURL.path)
        }

        try takeBackup()

        for _ in 1...Self.maximumAttempts {
            try patch(imageURL)
            restartAgent()
            if store.holdsWallpaper(imageURL, inStoreAt: storeURL) { return }
        }
        throw AllSpacesApplierError.verificationFailed(attempts: Self.maximumAttempts)
    }

    /// Writes the wallpaper into the store.
    private func patch(_ imageURL: URL) throws {
        do {
            try store.setWallpaper(imageURL, inStoreAt: storeURL)
        } catch let error as WallpaperStoreError {
            throw AllSpacesApplierError.storeFailure(reason: error.errorDescription ?? "")
        }
    }

    /// Takes the backup of the store once.
    ///
    /// The backup is never overwritten, so it always holds the store as it
    /// was before the app touched it.
    private func takeBackup() throws {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: storeURL, to: backupURL)
        } catch {
            throw AllSpacesApplierError.backupFailed(path: backupURL.path, reason: error.localizedDescription)
        }
    }

    /// Restarts the wallpaper agent, so it reads the store that was written.
    ///
    /// The caller waits until the agent is gone. The agent is started by
    /// launchd, so it reads the store on its own.
    nonisolated static func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // The agent is started by launchd, so a missing `killall` only
            // means that the agent keeps running. The check of the store
            // reports that.
        }
    }

    private static func message(for error: Error, imageURL: URL) -> String {
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "The wallpaper \(imageURL.lastPathComponent) could not be put on every Space. \(reason)"
    }
}
