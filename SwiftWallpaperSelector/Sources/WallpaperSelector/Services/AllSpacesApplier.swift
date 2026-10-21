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
///
/// The work runs on a queue of its own: it reads and writes files, restarts
/// the agent and reads the store again. That takes longer than the main
/// actor may be blocked, because the interface would freeze while the
/// desktop flickers.
@MainActor
class AllSpacesApplier {

    /// The backup of the store, taken once before the first write.
    ///
    /// The backup lives in the folder of the app, not next to the store.
    nonisolated static var defaultBackupURL: URL {
        SettingsManager.defaultSettingsDirectory
            .appendingPathComponent("WallpaperIndex.plist.backup", isDirectory: false)
    }

    /// Reports that the wallpaper could not be put on every Space.
    var onError: (@MainActor (String) -> Void)?

    /// Reports that the wallpaper is on every Space.
    var onApplied: (@MainActor () -> Void)?

    /// The queue the work runs on.
    ///
    /// The queue is serial, so two applies cannot write the store at the
    /// same time.
    private static let workQueue = DispatchQueue(
        label: "com.wallpaper-selector.all-spaces",
        qos: .userInitiated
    )

    private let store: WallpaperStore
    private let storeURL: URL
    private let backupURL: URL
    private let restartAgent: () -> Void

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
    /// The call returns at once, because the work runs on the queue of the
    /// applier. The failure is reported through `onError`, the success
    /// through `onApplied`. Both are called on the main actor.
    func apply(_ imageURL: URL) {
        let work = AllSpacesWork(
            store: store,
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: restartAgent
        )
        Self.workQueue.async { [weak self] in
            let result = work.run(imageURL)
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.onApplied?()
                case .failure(let error):
                    self.onError?(Self.message(for: error, imageURL: imageURL))
                }
            }
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

    nonisolated static func message(for error: Error, imageURL: URL) -> String {
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "The wallpaper \(imageURL.lastPathComponent) could not be put on every Space. \(reason)"
    }
}

/// The work of the applier.
///
/// It runs off the main actor, so it carries everything it needs on its own.
/// The restart closure is not `Sendable`, so the struct is unchecked: the
/// closure only runs on the queue of the applier.
private struct AllSpacesWork: @unchecked Sendable {
    let store: WallpaperStore
    let storeURL: URL
    let backupURL: URL
    let restartAgent: () -> Void

    /// The number of times the store is written before the apply is given up.
    ///
    /// shortcut: the agent can write the store from its own memory between
    /// the write and the restart, so the wallpaper is written again. Three
    /// tries are enough in practice; the apply fails when the agent keeps
    /// overwriting the store.
    private static let maximumAttempts = 3

    func run(_ imageURL: URL) -> Result<Void, Error> {
        Result { try applyWallpaper(imageURL) }
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
}
