import Foundation

/// The failure of an apply.
struct AllSpacesApplyFailure: Error, LocalizedError, Equatable {
    /// The wallpaper that could not be put on every Space.
    let imagePath: String
    /// Why the apply failed.
    let reason: String

    var errorDescription: String? {
        let name = URL(fileURLWithPath: imagePath).lastPathComponent
        return "The wallpaper \(name) could not be put on every Space. \(reason)"
    }
}

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

/// The wallpaper agent of macOS.
///
/// The agent is an XPC service of launchd, so `NSWorkspace` does not list
/// it. Its processes are found with `pgrep`.
struct WallpaperAgent: Sendable {
    /// Restarts the agent, so it reads the store again.
    var restart: @Sendable () -> Void
    /// The identifiers of the agent processes that run.
    var identifiers: @Sendable () -> [Int]
    /// The seconds the applier waits for the agent to come back.
    var restartTimeout: TimeInterval
    /// The seconds the store is given to settle after the agent came back.
    var settleTime: TimeInterval

    /// The agent of the Mac the app runs on.
    static let live = WallpaperAgent(
        restart: { AllSpacesApplier.restartWallpaperAgent() },
        identifiers: { AllSpacesApplier.runningAgentProcessIdentifiers() },
        restartTimeout: 5,
        settleTime: 0.3
    )
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

    /// Reports the result of the apply.
    ///
    /// The result is reported on the main actor: the failure when the
    /// wallpaper did not reach every Space, the success when it did.
    var onResult: (@MainActor (Result<Void, AllSpacesApplyFailure>) -> Void)?

    /// The queue the work runs on.
    ///
    /// The queue is serial, so two applies cannot write the store at the
    /// same time.
    private static let workQueue = DispatchQueue(
        label: "com.wallpaper-selector.all-spaces",
        qos: .userInitiated
    )

    /// The store the applier writes.
    ///
    /// A test reads it to make sure the store of macOS is never written.
    let storeURL: URL

    private let store: WallpaperStore
    private let backupURL: URL
    private let agent: WallpaperAgent

    init(
        storeURL: URL = WallpaperStore.defaultStoreURL,
        backupURL: URL = AllSpacesApplier.defaultBackupURL,
        agent: WallpaperAgent = .live
    ) {
        self.store = WallpaperStore()
        self.storeURL = storeURL
        self.backupURL = backupURL
        self.agent = agent
    }

    /// Puts the wallpaper on every Space.
    ///
    /// The call returns at once, because the work runs on the queue of the
    /// applier. The result is reported through `onResult` on the main actor.
    func apply(_ imageURL: URL) {
        let work = AllSpacesWork(
            store: store,
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent
        )
        Self.workQueue.async { [weak self] in
            let result = work.run(imageURL)
            Task { @MainActor in
                guard let self else { return }
                self.onResult?(result)
            }
        }
    }

    /// Restarts the wallpaper agent, so it reads the store that was written.
    ///
    /// The agent is started by launchd, so it comes back on its own. The
    /// `killall` only waits for itself, so the caller waits for the new
    /// agent with `AllSpacesWork.waitForAgent`.
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

    /// The identifiers of the running wallpaper agent processes.
    ///
    /// The agent is an XPC service of launchd, so `NSWorkspace` does not
    /// list it. `pgrep` finds it by its exact name. A missing `pgrep` gives
    /// no identifier at all.
    nonisolated static func runningAgentProcessIdentifiers() -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "WallpaperAgent"]
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// The work of the applier.
///
/// It runs off the main actor, so it carries everything it needs on its own.
/// The store holds closures, so the struct is unchecked: the closures only
/// run on the queue of the applier.
private struct AllSpacesWork: @unchecked Sendable {
    let store: WallpaperStore
    let storeURL: URL
    let backupURL: URL
    let agent: WallpaperAgent

    /// The number of times the store is written before the apply is given up.
    ///
    /// shortcut: the agent can write the store from its own memory while it
    /// is dying, so the wallpaper is written again. Three tries are enough
    /// in practice; the apply fails when the agent keeps overwriting the
    /// store.
    private static let maximumAttempts = 3

    /// The seconds between two looks at the processes of the agent.
    private static let pollInterval: TimeInterval = 0.05

    /// The seconds the store is given to settle when no agent can be seen.
    private static let fallbackPause: TimeInterval = 0.3

    func run(_ imageURL: URL) -> Result<Void, AllSpacesApplyFailure> {
        do {
            try applyWallpaper(imageURL)
            return .success(())
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failure(AllSpacesApplyFailure(imagePath: imageURL.path, reason: reason))
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
            // The agent is looked up before it is killed, so a new agent can
            // be told from the old one.
            let agentsBefore = agent.identifiers()
            try patch(imageURL)
            agent.restart()
            if waitForAgent(after: agentsBefore) {
                // The new agent reads the store and writes it again, so the
                // store is given a moment before it is checked.
                Thread.sleep(forTimeInterval: agent.settleTime)
            }
            if store.holdsWallpaper(imageURL, inStoreAt: storeURL) { return }
        }
        throw AllSpacesApplierError.verificationFailed(attempts: Self.maximumAttempts)
    }

    /// Waits until the agent has stopped and a new one runs.
    ///
    /// Returns `true` when a new agent process was seen. The store is only
    /// checked after the agent came back: an agent that is still alive can
    /// write the store from its own memory, and then the check would pass
    /// while the wallpaper is gone a moment later.
    private func waitForAgent(after previous: [Int]) -> Bool {
        guard !previous.isEmpty else {
            // shortcut: without a running agent there is nothing to watch,
            // so the store is checked after a short pause. Upgrade this when
            // the agent can be seen on every Mac.
            Thread.sleep(forTimeInterval: Self.fallbackPause)
            return false
        }

        let deadline = Date().addingTimeInterval(agent.restartTimeout)
        while true {
            let current = agent.identifiers()
            let oldIsGone = previous.allSatisfy { !current.contains($0) }
            let newAgentRuns = current.contains { !previous.contains($0) }
            if oldIsGone && newAgentRuns { return true }
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
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
