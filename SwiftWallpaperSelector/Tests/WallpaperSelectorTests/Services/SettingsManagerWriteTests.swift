import Foundation
import XCTest
@testable import WallpaperSelector

@MainActor
final class SettingsManagerWriteTests: XCTestCase {

    /// The write must not run on the main actor: the user interface would
    /// wait for the file write.
    func testTheSettingsFileIsWrittenOffTheMainActor() async throws {
        let context = try TestSettingsContext()
        let threads = WriteThreadRecorder()
        let manager = context.makeSettingsManager(beforeWrite: { threads.record() })

        manager.replace(WallpaperSettings(folderPaths: ["/written"]))
        await manager.waitForPendingWrites()

        XCTAssertTrue(threads.recordedAWrite, "The write has to run")
        XCTAssertFalse(threads.ranOnTheMainThread, "The write must not run on the main actor")
    }

    /// The queued write lands before the test asserts on the file.
    func testTheQueuedWriteLandsAfterTheFlush() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()

        manager.replace(WallpaperSettings(folderPaths: ["/flushed"]))
        manager.flushPendingWrites()

        XCTAssertEqual(
            try decodeSettings(at: manager.settingsURL).folderPaths,
            ["/flushed"]
        )
    }

    /// The writes run one after the other, so the last one is on disk.
    func testTheLastOfTwoRapidWritesIsOnDisk() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()

        manager.replace(WallpaperSettings(folderPaths: ["/first"]))
        manager.replace(WallpaperSettings(folderPaths: ["/second"]))
        manager.flushPendingWrites()

        XCTAssertEqual(
            try decodeSettings(at: manager.settingsURL).folderPaths,
            ["/second"]
        )
    }

    /// The settings file is deleted, so the watcher recreates it. A change
    /// that lands while the recreate waits must not be lost: the file has to
    /// end with the newest settings.
    func testAWriteThatLandsDuringTheRecreateKeepsTheNewerChange() async throws {
        let context = try TestSettingsContext()
        let gate = WriteGate()
        let manager = context.makeSettingsManager(beforeWrite: { gate.beforeWrite() })
        manager.replace(WallpaperSettings(folderPaths: ["/wallpapers"]))
        manager.flushPendingWrites()

        // The settings file is deleted, so the watcher recreates it.
        gate.pauseTheNextWrite()
        try FileManager.default.removeItem(at: manager.settingsURL)

        // The recreate waits for the write queue, so the change can land.
        await gate.waitUntilTheWriteWaits()

        manager.update { $0.currentWallpaper = "/wallpapers/new.jpg" }
        // The change gets the time to reach the disk before the recreate is
        // released, so the order of the two writes is fixed.
        _ = await waitUntil(timeout: 0.5) {
            (try? decodeSettings(at: manager.settingsURL))?.currentWallpaper == "/wallpapers/new.jpg"
        }
        gate.resumeTheWrite()
        // The file has to settle: both writes are done when it stops changing.
        let settled = await waitUntilTheFileStopsChanging(at: manager.settingsURL)
        XCTAssertTrue(settled, "The writes have to settle")
        await manager.waitForPendingWrites()

        XCTAssertEqual(
            manager.settings.currentWallpaper,
            "/wallpapers/new.jpg",
            "The change must stay in memory"
        )
        XCTAssertEqual(
            try decodeSettings(at: manager.settingsURL).currentWallpaper,
            "/wallpapers/new.jpg",
            "The newest settings have to be on disk"
        )
    }

    /// Waits for a condition instead of relying on a tight timeout.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// Waits until the settings file is not written again: the writes are
    /// done then.
    private func waitUntilTheFileStopsChanging(
        at url: URL,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastDate: Date?
        var stableChecks = 0
        while Date() < deadline {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let date = attributes?[.modificationDate] as? Date
            if date != nil, date == lastDate {
                stableChecks += 1
                if stableChecks >= 4 { return true }
            } else {
                stableChecks = 0
            }
            lastDate = date
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func decodeSettings(at url: URL) throws -> WallpaperSettings {
        try JSONDecoder().decode(WallpaperSettings.self, from: Data(contentsOf: url))
    }
}

/// Pauses the writes of the settings file.
///
/// The gate runs on the write queue, so a test can change the settings while
/// a write waits.
private final class WriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pausesTheNextWrite = false
    private var isWaiting = false
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private let resume = DispatchSemaphore(value: 0)

    /// Pauses the next write.
    func pauseTheNextWrite() {
        lock.lock()
        pausesTheNextWrite = true
        lock.unlock()
    }

    /// The seam the settings manager calls before every write.
    func beforeWrite() {
        lock.lock()
        let shouldPause = pausesTheNextWrite
        pausesTheNextWrite = false
        isWaiting = shouldPause
        let continuation = waitingContinuation
        waitingContinuation = nil
        lock.unlock()

        guard shouldPause else { return }
        // The test changes the settings and then lets the write continue.
        continuation?.resume()
        resume.wait()
        lock.lock()
        isWaiting = false
        lock.unlock()
    }

    /// Waits until a write waits at the gate.
    func waitUntilTheWriteWaits() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isWaiting {
                lock.unlock()
                continuation.resume()
                return
            }
            waitingContinuation = continuation
            lock.unlock()
        }
    }

    /// Lets the waiting write continue.
    func resumeTheWrite() {
        resume.signal()
    }
}

/// Records the thread that runs the write of the settings file.
private final class WriteThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = false
    private var onMainThread = false

    /// The seam the settings manager calls before every write.
    func record() {
        lock.lock()
        recorded = true
        onMainThread = Thread.isMainThread
        lock.unlock()
    }

    var recordedAWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var ranOnTheMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return onMainThread
    }
}
