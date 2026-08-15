import Foundation
import Combine
import SwiftUI

@MainActor
final class RotationViewModel: ObservableObject {

    @Published private(set) var isRunning: Bool = false

    @Published var intervalMinutes: RotationInterval = .off

    @Published var rotationAction: RotationAction = .shuffle

    @Published var historyLimit: Int = 10


    private let rotationService: RotationService


    init(rotationService: RotationService) {
        self.rotationService = rotationService
        _isRunning = Published(initialValue: rotationService.isRunning)
        _intervalMinutes = Published(initialValue: rotationService.settingsManager.settings.intervalMinutes)
        _rotationAction = Published(initialValue: rotationService.settingsManager.settings.rotationAction)
        _historyLimit = Published(initialValue: rotationService.settingsManager.settings.historyLimit)
    }


    func toggleRotation() {
        isRunning ? rotationService.stop() : rotationService.start()
    }

    func performTick() {
        rotationService.tick()
    }

    func setInterval(_ interval: RotationInterval) {
        intervalMinutes = interval
        rotationService.intervalSeconds = TimeInterval(interval.rawValue * 60)
    }

    func setRotationAction(_ action: RotationAction) {
        rotationAction = action
        rotationService.settingsManager.update { $0.rotationAction = action }
    }

    func setHistoryLimit(_ limit: Int) {
        historyLimit = limit
        rotationService.settingsManager.update { $0.historyLimit = limit }
    }


    var onRotationPerformed: (() -> Void)?
}
