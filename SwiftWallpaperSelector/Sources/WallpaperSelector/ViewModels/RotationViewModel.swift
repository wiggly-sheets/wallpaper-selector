import Foundation
import Combine
import SwiftUI

/// ViewModel that wraps `RotationService` to expose rotation state and actions
/// to the UI in a testable, observable way.
@MainActor
final class RotationViewModel: ObservableObject {
    // MARK: - Published properties exposed to the UI

    /// Indicates whether the rotation timer is currently running.
    @Published private(set) var isRunning: Bool = false

    /// Current rotation interval selection.
    @Published var intervalMinutes: RotationInterval = .off

    /// Current rotation action (shuffle, next, previous, etc.).
    @Published var rotationAction: RotationAction = .shuffle

    /// Limit for how many recent wallpapers are stored in history.
    @Published var historyLimit: Int = 10

    // MARK: - Dependencies

    private let rotationService: RotationService

    // MARK: - Initialization

    /// Creates a new `RotationViewModel`.
    /// - Parameter rotationService: The service that performs the actual rotation logic.
    init(rotationService: RotationService) {
        self.rotationService = rotationService
        // Sync initial state from the service
        _isRunning = Published(initialValue: rotationService.isRunning)
        _intervalMinutes = Published(initialValue: rotationService.settingsManager.settings.intervalMinutes)
        _rotationAction = Published(initialValue: rotationService.settingsManager.settings.rotationAction)
        _historyLimit = Published(initialValue: rotationService.settingsManager.settings.historyLimit)
    }

    // MARK: - Public Interface

    /// Toggles the rotation timer on or off.
    func toggleRotation() {
        isRunning ? rotationService.stop() : rotationService.start()
    }

    /// Triggers a single rotation step (used by UI shortcuts).
    func performTick() {
        rotationService.tick()
    }

    /// Updates the rotation interval based on a new `RotationInterval` value.
    func setInterval(_ interval: RotationInterval) {
        intervalMinutes = interval
        rotationService.intervalSeconds = TimeInterval(interval.rawValue * 60)
    }

    /// Updates the rotation action based on a new `RotationAction` value.
    func setRotationAction(_ action: RotationAction) {
        rotationAction = action
        rotationService.settingsManager.update { $0.rotationAction = action }
    }

    /// Adjusts the history limit used when selecting the next wallpaper.
    func setHistoryLimit(_ limit: Int) {
        historyLimit = limit
        rotationService.settingsManager.update { $0.historyLimit = limit }
    }

    // MARK: - Observers (optional)

    /// Hook for UI that wants to react when a rotation occurs.
    var onRotationPerformed: (() -> Void)?
}