import Foundation
import Carbon

@MainActor
class HotKeyManager {

    private(set) var registeredHotKeys: [EventHotKeyRef] = []

    var onHotKeyPressed: ((String) -> Void)?

    /// Reports why a shortcut could not be registered. `nil` means every
    /// shortcut registered fine.
    var onRegistrationError: ((String?) -> Void)?


    private var settingsManager: SettingsManager
    private var eventHandlerUPP: EventHandlerUPP?
    private var eventHandler: EventHandlerRef?
    private var managerBox: WeakHotKeyManagerBox?

    /// The signature of the hot keys. It is app specific, so another app
    /// cannot register a hot key with the same id.
    private static let hotKeySignature = OSType(0x57534C53) // 'WSLS'

    /// The id of the next hot key. It only grows, so a re-registered hot key
    /// never reuses the id of another one.
    private var nextHotKeyID: UInt32 = 1


    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        installEventHandler()
    }

    deinit {
        for hotKey in registeredHotKeys {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        // On macOS the event handler UPP is a plain function pointer, so
        // dropping the Swift closure is what releases it.
        eventHandlerUPP = nil
    }


    func register() {
        registerShortcuts(settingsManager.settings.shortcuts)
    }

    func unregisterAll() {
        for ref in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys = []
        managerBox?.removeAllIdentifiers()
    }

    /// Re-registers the given shortcuts. The value is passed in so the caller
    /// never has to read the settings again while a change is being published.
    func updateShortcuts(_ shortcuts: Shortcuts) {
        registerShortcuts(shortcuts)
    }


    private func registerShortcuts(_ shortcuts: Shortcuts) {
        unregisterAll()

        var failures: [String] = []

        if let showMain = shortcuts.showMain {
            register(shortcut: showMain, identifier: "showMain", failures: &failures)
        }

        if let showPreview = shortcuts.showPreview {
            register(shortcut: showPreview, identifier: "showPreview", failures: &failures)
        }

        if let showMenu = shortcuts.showMenu {
            register(shortcut: showMenu, identifier: "showMenu", failures: &failures)
        }

        onRegistrationError?(failures.isEmpty ? nil : failures.joined(separator: " "))
    }


    private func register(shortcut: String, identifier: String, failures: inout [String]) {
        guard let keyCombo = parseAccelerator(shortcut) else {
            failures.append("Could not read the shortcut \(shortcut).")
            return
        }
        guard registerHotKey(keyCombo, identifier: identifier) else {
            failures.append(
                "Could not register the shortcut \(shortcut). Another app may already use it."
            )
            return
        }
    }

    private func registerHotKey(_ combo: KeyCombo, identifier: String) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let id = nextHotKeyID
        nextHotKeyID += 1
        let result = RegisterEventHotKey(
            UInt32(combo.keyCode),
            UInt32(combo.modifiers),
            EventHotKeyID(signature: Self.hotKeySignature, id: id),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if result == noErr, let ref = hotKeyRef {
            registeredHotKeys.append(ref)
            managerBox?.setIdentifier(identifier, for: id)
            return true
        }

        print("[HotKeyManager] Failed to register hot-key '\(identifier)': \(result)")
        return false
    }

    func parseAccelerator(_ string: String) -> KeyCombo? {
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
            case 0x2318:
                modifiers |= UInt32(cmdKey)
            case 0x21E7:
                modifiers |= UInt32(shiftKey)
            case 0x2325:
                modifiers |= UInt32(optionKey)
            case 0x2303:
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
        let box = WeakHotKeyManagerBox()
        box.manager = self
        managerBox = box
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
            let box = Unmanaged<WeakHotKeyManagerBox>.fromOpaque(userData).takeUnretainedValue()
            guard let manager = box.manager else { return noErr }
            // The identifier is resolved here, not in the task below: a
            // re-registration clears the map, so a press that waits for the
            // main actor would be lost.
            guard let action = box.identifier(for: hotKeyID.id) else { return noErr }
            Task { @MainActor in
                manager.onHotKeyPressed?(action)
            }
            return noErr
        }
        guard let eventHandlerUPP else { return }
        InstallEventHandler(
            GetEventDispatcherTarget(),
            eventHandlerUPP,
            1,
            &eventType,
            Unmanaged.passUnretained(box).toOpaque(),
            &eventHandler
        )
    }
}

/// Keeps the manager reachable from the Carbon event handler without keeping
/// it alive: the handler only holds the box, the box only holds a weak link.
///
/// The hot-key identifiers live here too, so the Carbon handler can resolve
/// the pressed shortcut without waiting for the main actor.
private final class WeakHotKeyManagerBox {
    weak var manager: HotKeyManager?

    private let lock = NSLock()
    private var identifiers: [UInt32: String] = [:]

    func identifier(for id: UInt32) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return identifiers[id]
    }

    func setIdentifier(_ identifier: String, for id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        identifiers[id] = identifier
    }

    func removeAllIdentifiers() {
        lock.lock()
        defer { lock.unlock() }
        identifiers.removeAll()
    }
}


struct KeyCombo: Sendable {
    let keyCode: UInt16
    let modifiers: UInt32
}
