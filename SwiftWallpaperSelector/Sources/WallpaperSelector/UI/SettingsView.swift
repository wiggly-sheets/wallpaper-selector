import SwiftUI
import AppKit

/// Settings view that mirrors the original ContentView functionality,
/// now using SettingsViewModel for all state and mutations.
struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddFolder = false
    @State private var showingAddTheme = false
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.symbol).tag(category)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(minWidth: 190, idealWidth: 210)
        } detail: {
            Form {
                // MARK: - General

                if selectedCategory == .general {
                Section("General") {
                    Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                        .accessibilityLabel("Launch at login toggle")
                        .onChange(of: viewModel.launchAtLogin) { newValue in
                            viewModel.setLaunchAtLogin(newValue)
                        }

                    Picker("Recent Wallpapers", selection: $viewModel.historyLimit) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityLabel("Recent wallpapers radio group")
                    .onChange(of: viewModel.historyLimit) { newValue in
                        viewModel.setHistoryLimit(newValue)
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Settings Location")
                            Text(viewModel.settingsFolderPath ?? "Application Support")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Choose…", action: viewModel.chooseSettingsFolder)
                        if viewModel.settingsFolderPath != nil {
                            Button("Default", action: viewModel.useDefaultSettingsFolder)
                        }
                    }
                }
                }

                // MARK: - Appearance

                if selectedCategory == .appearance {
                Section("Appearance") {
                    Picker("Theme Source", selection: $viewModel.themeSource) {
                        ForEach(ThemeSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityLabel("Theme source radio group")
                    .onChange(of: viewModel.themeSource) { newValue in
                        viewModel.setThemeSource(newValue)
                    }

                    Toggle("Match System Appearance", isOn: $viewModel.matchSystemAppearance)
                        .accessibilityLabel("Match system appearance toggle")
                        .onChange(of: viewModel.matchSystemAppearance) { viewModel.setMatchSystemAppearance($0) }

                    Toggle("All Spaces", isOn: $viewModel.allSpaces)
                        .accessibilityLabel("All spaces toggle")
                        .onChange(of: viewModel.allSpaces) { viewModel.setAllSpaces($0) }

                    // Appearance-specific theme overrides
                    if !viewModel.themes.isEmpty {
                        Picker("Light Theme", selection: $viewModel.appearanceLightThemeID) {
                            Text("None").tag(Optional<String>.none as String?)
                            ForEach(viewModel.themes) { theme in
                                Text(theme.displayName).tag(Optional(theme.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: viewModel.appearanceLightThemeID) { _ in viewModel.persistAppearanceOverrides() }

                        Picker("Dark Theme", selection: $viewModel.appearanceDarkThemeID) {
                            Text("None").tag(Optional<String>.none as String?)
                            ForEach(viewModel.themes) { theme in
                                Text(theme.displayName).tag(Optional(theme.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: viewModel.appearanceDarkThemeID) { _ in viewModel.persistAppearanceOverrides() }
                    }

                    // Appearance-specific wallpaper overrides (for "All Folders")
                    Section("Appearance Overrides (All Folders)") {
                        Picker("Light Wallpaper", selection: $viewModel.allFoldersLightWallpaper) {
                            Text("None").tag(Optional<String>.none as String?)
                            ForEach(viewModel.currentThemeImages, id: \.self) { url in
                                Text(url.lastPathComponent).tag(Optional(url.path))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: viewModel.allFoldersLightWallpaper) { _ in viewModel.persistAppearanceOverrides() }

                        Picker("Dark Wallpaper", selection: $viewModel.allFoldersDarkWallpaper) {
                            Text("None").tag(Optional<String>.none as String?)
                            ForEach(viewModel.currentThemeImages, id: \.self) { url in
                                Text(url.lastPathComponent).tag(Optional(url.path))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: viewModel.allFoldersDarkWallpaper) { _ in viewModel.persistAppearanceOverrides() }
                    }
                }
                }

                // MARK: - Keyboard Shortcuts

                if selectedCategory == .shortcuts {
                Section("Keyboard Shortcuts") {
                    ShortcutRecorder(label: "Show Main Window", shortcut: viewModel.shortcuts.showMain) {
                        viewModel.setShowMainShortcut($0)
                    }
                    ShortcutRecorder(label: "Show Preview", shortcut: viewModel.shortcuts.showPreview) {
                        viewModel.setShowPreviewShortcut($0)
                    }
                    ShortcutRecorder(label: "Open Menu Bar Menu", shortcut: viewModel.shortcuts.showMenu) {
                        viewModel.setShowMenuShortcut($0)
                    }
                }
                }

                // MARK: - Folders

                if selectedCategory == .folders {
                Section("Folders") {
                    Label("Count: \(viewModel.folderPaths.count)", systemImage: "folder")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(viewModel.folderPaths, id: \.self) { path in
                        Text(path)
                            .font(.subheadline)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach {
                            viewModel.removeFolder(viewModel.folderPaths[$0])
                        }
                    }

                    Button(action: {
                        showingAddFolder = true
                    }) {
                        Label("Add Folder", systemImage: "plus.folder")
                    }
                    .accessibilityLabel("Add folder button")
                }
                }

                // MARK: - Themes

                if selectedCategory == .themes {
                Section("Themes") {
                    Label("Count: \(viewModel.themes.count)", systemImage: "tag")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(viewModel.themes) { theme in
                        VStack(alignment: .leading) {
                            Text(theme.displayName)
                                .font(.subheadline)
                            Text("Folders: \(theme.folderPaths.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach {
                            viewModel.removeTheme(id: viewModel.themes[$0].id)
                        }
                    }

                    Button(action: {
                        showingAddTheme = true
                    }) {
                        Label("Add Theme", systemImage: "plus.app")
                    }
                    .accessibilityLabel("Add theme button")
                }
                }

                // MARK: - Rotation Controls

                if selectedCategory == .rotation {
                Section("Rotation") {
                    Picker("Interval", selection: $viewModel.intervalMinutes) {
                        ForEach(RotationInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .accessibilityLabel("Rotation interval picker")
                    .onChange(of: viewModel.intervalMinutes) { viewModel.setInterval($0) }

                    Picker("Action", selection: $viewModel.rotationAction) {
                        ForEach(RotationAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .accessibilityLabel("Rotation action picker")
                    .onChange(of: viewModel.rotationAction) { viewModel.setRotationAction($0) }
                }
                }

                // MARK: - Save

                if selectedCategory == .general {
                    Section {
                        Text("Changes save automatically.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selectedCategory.title)
            .frame(minWidth: 520, minHeight: 560)
        }
        .navigationSplitViewStyle(.balanced)
        // Escape closes the Settings window (unless a shortcut is being recorded,
        // in which case the recorder consumes Escape to cancel).
        .overlay(
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .sheet(isPresented: $showingAddFolder) {
            AddFolderView { viewModel.addFolder($0) }
        }
        .sheet(isPresented: $showingAddTheme) {
            AddThemeView { viewModel.addTheme($0) }
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, folders, themes, rotation

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .shortcuts: "keyboard"
        case .folders: "folder"
        case .themes: "paintpalette"
        case .rotation: "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Shortcut Recorder

/// Click-to-record keyboard shortcut field. Emits an accelerator string
/// compatible with `HotKeyManager.parseAccelerator` (modifier glyphs +
/// letter/digit/F-key, e.g. "⌘⇧X").
struct ShortcutRecorder: View {
    let label: String
    let shortcut: String?
    let onChange: (String?) -> Void

    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(action: { isRecording = true }) {
                Text(isRecording ? "Recording… (Esc to cancel)" : (shortcut ?? "Click to set"))
            }
            .buttonStyle(.bordered)
            .disabled(isRecording)

            KeyboardCaptureView(
                isActive: isRecording,
                onCommit: { combo in
                    isRecording = false
                    onChange(combo)
                },
                onCancel: { isRecording = false },
                onClear: {
                    isRecording = false
                    onChange(nil)
                }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Keyboard Capture

/// Backs `ShortcutRecorder` with an `NSView` that captures key events via a
/// local monitor while recording is active.
struct KeyboardCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> KeyboardCaptureHost {
        let view = KeyboardCaptureHost()
        view.isActive = isActive
        view.onCommit = onCommit
        view.onCancel = onCancel
        view.onClear = onClear
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureHost, context: Context) {
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.onClear = onClear
        nsView.isActive = isActive
    }
}

final class KeyboardCaptureHost: NSView {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onClear: (() -> Void)?

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            isActive ? beginCapturing() : endCapturing()
        }
    }

    private var monitor: Any?

    /// keyCode → function-key label, matching HotKeyManager.keyCodeForCharacter.
    private let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12"
    ]

    deinit {
        endCapturing()
    }

    private func beginCapturing() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event -> NSEvent? in
            guard let self = self, self.isActive else { return event }
            return self.handle(event)
        }
    }

    private func endCapturing() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Escape cancels recording (does not close the window).
        if event.keyCode == 53 {
            endCapturing()
            onCancel?()
            return nil
        }
        // Backspace / Delete clears the shortcut.
        if event.keyCode == 51 || event.keyCode == 117 {
            endCapturing()
            onClear?()
            return nil
        }
        guard let combo = comboString(for: event) else {
            return nil
        }
        endCapturing()
        onCommit?(combo)
        return nil
    }

    private func comboString(for event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Requires at least one of ⌘/⌃/⌥ (shift-only is allowed in addition).
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }

        var result = ""
        if flags.contains(.control) { result += "\u{2303}" }   // ⌃
        if flags.contains(.option) { result += "\u{2325}" }  // ⌥
        if flags.contains(.shift) { result += "\u{21E7}" }  // ⇧
        if flags.contains(.command) { result += "\u{2318}" } // ⌘

        guard let glyph = keyGlyph(for: event) else { return nil }
        return result + glyph
    }

    private func keyGlyph(for event: NSEvent) -> String? {
        if let functionKey = functionKeys[event.keyCode] {
            return functionKey
        }
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard characters.count == 1, let first = characters.first else { return nil }
        guard first.isLetter || first.isNumber else { return nil }
        return characters
    }
}
