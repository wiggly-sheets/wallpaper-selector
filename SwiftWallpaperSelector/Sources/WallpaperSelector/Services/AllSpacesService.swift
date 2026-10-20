import AppKit
import ApplicationServices
import Foundation

enum AllSpacesManualFallbackReason: Equatable, Sendable {
    case accessibilityPermissionRequired
    case couldNotOpenWallpaperSettings
    case systemSettingsUnavailable
    case showOnAllSpacesControlNotFound
    case automationFailed(String)
}

enum AllSpacesApplicationResult: Equatable, Sendable {
    case applied(enabled: Bool)
    case alreadySet(enabled: Bool)
    case manualActionRequired(enabled: Bool, reason: AllSpacesManualFallbackReason)
}

enum AllSpacesAutomationResult: Sendable {
    case applied
    case alreadySet
    case manualActionRequired(AllSpacesManualFallbackReason)
}

/// Serializes Accessibility changes to System Settings.
///
/// Every request reads the actual checkbox value. Nothing is inferred from the
/// last requested value, because the user can change the setting outside this
/// app at any time.
@MainActor
final class AllSpacesService {
    typealias Completion = @MainActor (AllSpacesApplicationResult) -> Void
    typealias Automation = @Sendable (_ processIdentifier: pid_t, _ enabled: Bool) -> AllSpacesAutomationResult

    var onResult: Completion?

    private struct Request {
        let enabled: Bool
        let completion: Completion?
    }

    private let wallpaperSettingsURL: URL
    private let openWallpaperSettings: @MainActor (URL) -> Bool
    private let systemSettingsProcessIdentifier: @MainActor () -> pid_t?
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let requestAccessibilityPermission: @MainActor () -> Void
    private let automation: Automation
    private let automationQueue: DispatchQueue
    private let systemSettingsWaitAttempts: Int
    private let systemSettingsWaitInterval: TimeInterval

    private var pendingRequests: [Request] = []
    private var isProcessing = false

    init(
        wallpaperSettingsURL: URL = URL(
            string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        )!,
        openWallpaperSettings: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        systemSettingsProcessIdentifier: @escaping @MainActor () -> pid_t? = {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
                .first?
                .processIdentifier
        },
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        requestAccessibilityPermission: @escaping @MainActor () -> Void = {
            AXIsProcessTrustedWithOptions([
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary)
        },
        automation: @escaping Automation = { processIdentifier, enabled in
            AllSpacesService.automate(processIdentifier: processIdentifier, enabled: enabled)
        },
        automationQueue: DispatchQueue = DispatchQueue(
            label: "com.wallpaper-selector.all-spaces",
            qos: .userInitiated
        ),
        systemSettingsWaitAttempts: Int = 40,
        systemSettingsWaitInterval: TimeInterval = 0.25
    ) {
        self.wallpaperSettingsURL = wallpaperSettingsURL
        self.openWallpaperSettings = openWallpaperSettings
        self.systemSettingsProcessIdentifier = systemSettingsProcessIdentifier
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.requestAccessibilityPermission = requestAccessibilityPermission
        self.automation = automation
        self.automationQueue = automationQueue
        self.systemSettingsWaitAttempts = systemSettingsWaitAttempts
        self.systemSettingsWaitInterval = systemSettingsWaitInterval
    }

    /// Enqueues an ordered request. The completion and `onResult` are always
    /// called on the main actor, in the same order as the requests.
    func setEnabled(_ enabled: Bool, completion: Completion? = nil) {
        pendingRequests.append(Request(enabled: enabled, completion: completion))
        processNextRequestIfNeeded()
    }

    private func processNextRequestIfNeeded() {
        guard !isProcessing, let request = pendingRequests.first else { return }
        isProcessing = true

        guard openWallpaperSettings(wallpaperSettingsURL) else {
            finishCurrentRequest(
                with: .manualActionRequired(
                    enabled: request.enabled,
                    reason: .couldNotOpenWallpaperSettings
                )
            )
            return
        }

        guard isAccessibilityTrusted() else {
            requestAccessibilityPermission()
            finishCurrentRequest(
                with: .manualActionRequired(
                    enabled: request.enabled,
                    reason: .accessibilityPermissionRequired
                )
            )
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let processIdentifier = await waitForSystemSettingsProcess() else {
                finishCurrentRequest(
                    with: .manualActionRequired(
                        enabled: request.enabled,
                        reason: .systemSettingsUnavailable
                    )
                )
                return
            }

            let automation = self.automation
            let enabled = request.enabled
            let automationQueue = self.automationQueue
            automationQueue.async { [weak self] in
                let result = automation(processIdentifier, enabled)
                guard let self else { return }
                Task { @MainActor in
                    self.finishCurrentRequest(with: Self.applicationResult(from: result, enabled: enabled))
                }
            }
        }
    }

    private func waitForSystemSettingsProcess() async -> pid_t? {
        for _ in 0..<systemSettingsWaitAttempts {
            if let processIdentifier = systemSettingsProcessIdentifier() {
                return processIdentifier
            }
            try? await Task.sleep(nanoseconds: UInt64(systemSettingsWaitInterval * 1_000_000_000))
        }
        return nil
    }

    private func finishCurrentRequest(with result: AllSpacesApplicationResult) {
        guard let request = pendingRequests.first else { return }
        pendingRequests.removeFirst()
        isProcessing = false
        request.completion?(result)
        onResult?(result)
        processNextRequestIfNeeded()
    }

    private nonisolated static func applicationResult(
        from result: AllSpacesAutomationResult,
        enabled: Bool
    ) -> AllSpacesApplicationResult {
        switch result {
        case .applied:
            return .applied(enabled: enabled)
        case .alreadySet:
            return .alreadySet(enabled: enabled)
        case .manualActionRequired(let reason):
            return .manualActionRequired(enabled: enabled, reason: reason)
        }
    }

    nonisolated static func automate(
        processIdentifier: pid_t,
        enabled: Bool
    ) -> AllSpacesAutomationResult {
        let application = AXUIElementCreateApplication(processIdentifier)
        let deadline = Date().addingTimeInterval(10)

        while Date() < deadline {
            if let checkbox = findShowOnAllSpacesCheckbox(in: application) {
                return setCheckbox(checkbox, enabled: enabled)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        return .manualActionRequired(.showOnAllSpacesControlNotFound)
    }

    private nonisolated static func findShowOnAllSpacesCheckbox(
        in application: AXUIElement
    ) -> AXUIElement? {
        var remaining: [AXUIElement] = [application]
        var inspectedElementCount = 0

        while let element = remaining.popLast(), inspectedElementCount < 5_000 {
            inspectedElementCount += 1

            if stringAttribute(kAXRoleAttribute as CFString, of: element) == kAXCheckBoxRole,
               metadata(of: element).contains(where: isShowOnAllSpacesMetadata) {
                return element
            }

            remaining.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute as CFString, of: element))
        }
        return nil
    }

    private nonisolated static func setCheckbox(
        _ checkbox: AXUIElement,
        enabled: Bool
    ) -> AllSpacesAutomationResult {
        let desiredValue = enabled ? 1 : 0
        guard let currentValue = numberAttribute(kAXValueAttribute as CFString, of: checkbox) else {
            return .manualActionRequired(.automationFailed("The checkbox value could not be read."))
        }
        guard currentValue.intValue != desiredValue else { return .alreadySet }

        let pressError = AXUIElementPerformAction(checkbox, kAXPressAction as CFString)
        guard pressError == .success else {
            return .manualActionRequired(
                .automationFailed("Accessibility could not press the checkbox (error \(pressError.rawValue)).")
            )
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if numberAttribute(kAXValueAttribute as CFString, of: checkbox)?.intValue == desiredValue {
                return .applied
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return .manualActionRequired(.automationFailed("The checkbox did not retain the requested value."))
    }

    private nonisolated static func metadata(of element: AXUIElement) -> [String] {
        let attributes: [CFString] = [
            kAXIdentifierAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString
        ]
        return attributes.compactMap { stringAttribute($0, of: element) }
    }

    private nonisolated static func isShowOnAllSpacesMetadata(_ value: String) -> Bool {
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()

        // AXIdentifier is usually language-independent. The additional labels
        // cover common System Settings localizations while an unknown layout
        // safely falls back to manual action rather than toggling the wrong UI.
        let knownFragments = [
            "showonallspaces",
            "aufallenspacesanzeigen",
            "affichersurtouslesespaces",
            "mostrarentodoslosespacios",
            "mostrasututtilispazi",
            "mostraremtodososespacos",
            "toonopallespaces",
            "すべての操作スペースに表示",
            "在所有空间中显示",
            "在所有空間中顯示",
            "모든space에표시"
        ]
        return knownFragments.contains(where: normalized.contains)
    }

    private nonisolated static func stringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private nonisolated static func numberAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? NSNumber
    }

    private nonisolated static func elementArrayAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
