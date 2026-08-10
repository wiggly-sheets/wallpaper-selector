import Foundation
import Carbon

/// Manages global keyboard shortcuts using the Carbon `RegisterEventHotKey` API.
///
/// Reads shortcut definitions from `SettingsManager.settings.shortcuts` and
/// registers/unregisters them when the settings change. Each hot-key triggers
/// a user-defined action (show main window, show preview, open menu).
final class HotKeyManager {
    // MARK: - Public

    /// The currently registered hot-key references, for deregistration.
    private(set) var registeredHotKeys: [EventHotKeyRef] = []

    /// Closure called when a hot-key is pressed.
    var onHotKeyPressed: ((String) -> Void)?

    // MARK: - Private

    private var settingsManager: SettingsManager
    private var eventHandlerUPP: EventHandlerUPP?
    private var eventHandler: EventHandlerRef?
    private var hotKeyIdentifiers: [UInt32: String] = [:]

    // MARK: - Init

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    // MARK: - Public API

    /// Register all hot-keys defined in the current settings.
    func register() {
        unregisterAll()

        let shortcuts = settingsManager.settings.shortcuts

        if let showMain = shortcuts.showMain,
           let keyCombo = parseAccelerator(showMain) {
            registerHotKey(keyCombo, identifier: "showMain")
        }

        if let showPreview = shortcuts.showPreview,
           let keyCombo = parseAccelerator(showPreview) {
            registerHotKey(keyCombo, identifier: "showPreview")
        }

        if let showMenu = shortcuts.showMenu,
           let keyCombo = parseAccelerator(showMenu) {
            registerHotKey(keyCombo, identifier: "showMenu")
        }
    }

    /// Unregister all currently registered hot-keys.
    func unregisterAll() {
        for ref in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys = []
        hotKeyIdentifiers = [:]
    }

    /// Update hot-keys when settings change.
    func updateShortcuts() {
        register()
    }

    // MARK: - Private

    private func registerHotKey(_ combo: KeyCombo, identifier: String) {
        var hotKeyRef: EventHotKeyRef?
        let id = UInt32(registeredHotKeys.count + 1)
        let result = RegisterEventHotKey(
            UInt32(combo.keyCode),
            UInt32(combo.modifiers),
            EventHotKeyID(signature: OSType(0), id: id),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if result == noErr, let ref = hotKeyRef {
            registeredHotKeys.append(ref)
            hotKeyIdentifiers[id] = identifier
        } else {
            print("[HotKeyManager] Failed to register hot-key '\(identifier)': \(result)")
        }
    }

    /// Parse a string like "⌘⇧S" or "⌃⌥P" into a `KeyCombo`.
    /// Returns `nil` if the string cannot be parsed.
    func parseAccelerator(_ string: String) -> KeyCombo? {
        // Existing Electron settings use token notation; native recorder stores
        // compact glyph notation. Accept both so migration does not drop keys.
        let tokenized = string.split(separator: "+").map(String.init)
        if tokenized.count > 1 {
            var modifiers: UInt32 = 0
            var key: String?
            for token in tokenized {
                switch token.lowercased() {
                case "command", "cmd", "commandorcontrol", "controlorcommand": modifiers |= UInt32(cmdKey)
                case "control", "ctrl": modifiers |= UInt32(controlKey)
                case "option", "alt": modifiers |= UInt32(optionKey)
                case "shift": modifiers |= UInt32(shiftKey)
                default: key = token
                }
            }
            guard let key, let keyCode = keyCodeForKeyName(key) else { return nil }
            return KeyCombo(keyCode: keyCode, modifiers: modifiers)
        }

        var modifiers: UInt32 = 0
        var keyName = ""

        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x2318: // ⌘ Command
                modifiers |= UInt32(cmdKey)
            case 0x21E7: // ⇧ Shift
                modifiers |= UInt32(shiftKey)
            case 0x2325: // ⌥ Option/Alt
                modifiers |= UInt32(optionKey)
            case 0x2303: // ⌃ Control
                modifiers |= UInt32(controlKey)
            default:
                keyName.unicodeScalars.append(scalar)
            }
        }

        guard let keyCode = keyCodeForKeyName(keyName) else { return nil }
        return KeyCombo(keyCode: keyCode, modifiers: modifiers)
    }

    private func keyCodeForKeyName(_ key: String) -> UInt16? {
        let keyCodes: [String: UInt16] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
            "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
            "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35,
            "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45,
            "M": 46, ".": 47, "`": 50
        ]
        let upper = key.uppercased()
        if let code = keyCodes[upper] { return code }
        switch upper {
        case "F1":  return 122
        case "F2":  return 120
        case "F3":  return 99
        case "F4":  return 118
        case "F5":  return 96
        case "F6":  return 97
        case "F7":  return 98
        case "F8":  return 100
        case "F9":  return 101
        case "F10": return 109
        case "F11": return 103
        case "F12": return 111
        default: return nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        eventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let identifier = manager.hotKeyIdentifiers[hotKeyID.id] {
                DispatchQueue.main.async { manager.onHotKeyPressed?(identifier) }
            }
            return noErr
        }
        guard let eventHandlerUPP else { return }
        InstallEventHandler(
            GetEventDispatcherTarget(),
            eventHandlerUPP,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}

// MARK: - Supporting Types

/// A parsed hot-key combination.
struct KeyCombo {
    let keyCode: UInt16
    let modifiers: UInt32
}
