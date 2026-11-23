import SwiftUI
import AppKit
import Combine

// The system Settings window has no sidebar toggle.
private struct SidebarToggleRemoval: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

// shortcut: the enabled state lives in the view model and is tested there, but no test can see whether this binding is negated, upgrade when a UI test harness exists
struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddFolder = false
    @State private var showingAddTheme = false
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.symbol)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .modifier(SidebarToggleRemoval())
        } detail: {
            Form {
                switch selectedCategory {
                case .general:
                    generalPane
                case .appearance:
                    appearancePane
                case .spaces:
                    spacesPane
                case .shortcuts:
                    shortcutsPane
                case .folders:
                    foldersPane
                case .themes:
                    themesPane
                case .rotation:
                    rotationPane
                }
            }
            .formStyle(.grouped)
            .onChange(of: selectedCategory) { category in
                if category == .spaces {
                    viewModel.refreshSpaces()
                }
            }
            // The Current badge is stale while the window stays open: macOS
            // changes the Space without telling this view.
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.activeSpaceDidChangeNotification
                )
            ) { _ in
                if selectedCategory == .spaces {
                    viewModel.refreshSpaces()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                if selectedCategory == .spaces {
                    viewModel.refreshSpaces()
                }
            }
            .navigationTitle(selectedCategory.title)
            .frame(minWidth: 520, minHeight: 560)
        }
        .navigationSplitViewStyle(.balanced)
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
            AddThemeView(availableFolders: viewModel.folderPaths) {
                viewModel.addTheme($0)
            }
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
    }

    @ViewBuilder
    private var generalPane: some View {
        Section {
            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .accessibilityLabel("Launch at login toggle")
                .help("Opens Wallpaper Selector when you log in.")

            Toggle("Show Menu Bar Icon", isOn: $viewModel.showMenuBarItem)
                .accessibilityLabel("Show menu bar icon toggle")
                .help("Shows the icon in the menu bar.")
                .onChange(of: viewModel.showMenuBarItem) { viewModel.setShowMenuBarItem($0) }

            if let message = viewModel.launchAtLoginMessage {
                HStack(alignment: .firstTextBaseline) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 12)
                    Button("Open Login Items\u{2026}", action: viewModel.openLaunchAtLoginSettings)
                        .controlSize(.small)
                }
            }

            Picker("Recent Wallpapers", selection: $viewModel.historyLimit) {
                Text("5").tag(5)
                Text("10").tag(10)
                Text("20").tag(20)
            }
            .accessibilityLabel("Recent wallpapers")
            .onChange(of: viewModel.historyLimit) { newValue in
                viewModel.setHistoryLimit(newValue)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings Location")
                    Text(viewModel.settingsFolderPath ?? "Application Support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button("Choose\u{2026}", action: viewModel.chooseSettingsFolder)
                    if viewModel.settingsFolderPath != nil {
                        Button("Default", action: viewModel.useDefaultSettingsFolder)
                    }
                }
                .controlSize(.small)
            }

            if let errorMessage = viewModel.settingsErrorMessage {
                errorRow(errorMessage)
            }
            if let errorMessage = viewModel.wallpaperErrorMessage {
                errorRow(errorMessage)
            }
        } footer: {
            Text("When the icon is hidden, open Wallpaper Selector again to show the main window.")
        }
    }

    @ViewBuilder
    private var appearancePane: some View {
        Section {
            Picker("Theme Source", selection: $viewModel.themeSource) {
                ForEach(ThemeSource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .accessibilityLabel("Theme source")
            .onChange(of: viewModel.themeSource) { newValue in
                viewModel.setThemeSource(newValue)
            }

            Toggle("Match System Appearance", isOn: $viewModel.matchSystemAppearance)
                .accessibilityLabel("Match system appearance toggle")
                .onChange(of: viewModel.matchSystemAppearance) { viewModel.setMatchSystemAppearance($0) }

            Toggle("All Spaces", isOn: $viewModel.allSpaces)
                .accessibilityLabel("All spaces toggle")
                // The toggle can always be turned off: a setting that was
                // stored on a newer macOS must be clearable here.
                .disabled(!AllSpacesSupport.isAvailable && !viewModel.allSpaces)
                .help(AllSpacesSupport.isAvailable
                      ? "Puts the wallpaper on every Space"
                      : "Needs macOS 14 or newer.")
                .onChange(of: viewModel.allSpaces) { viewModel.setAllSpaces($0) }

            if !viewModel.themes.isEmpty {
                Picker("Light Theme", selection: $viewModel.appearanceLightThemeID) {
                    Text("None").tag(Optional<String>.none as String?)
                    ForEach(viewModel.themes) { theme in
                        Text(theme.displayName).tag(Optional(theme.id))
                    }
                }
                .onChange(of: viewModel.appearanceLightThemeID) { _ in viewModel.persistAppearanceOverrides() }

                Picker("Dark Theme", selection: $viewModel.appearanceDarkThemeID) {
                    Text("None").tag(Optional<String>.none as String?)
                    ForEach(viewModel.themes) { theme in
                        Text(theme.displayName).tag(Optional(theme.id))
                    }
                }
                .onChange(of: viewModel.appearanceDarkThemeID) { _ in viewModel.persistAppearanceOverrides() }
            }
        } footer: {
            if !AllSpacesSupport.isAvailable {
                Text("All Spaces needs macOS 14 or newer.")
            }
        }

        Section {
            Picker("Light Wallpaper", selection: $viewModel.allFoldersLightWallpaper) {
                Text("None").tag(Optional<String>.none as String?)
                ForEach(viewModel.allFoldersLightWallpaperImages, id: \.self) { url in
                    Text(url.lastPathComponent).tag(Optional(url.path))
                }
            }
            .disabled(viewModel.isGlobalLightPinDisabled)
            .onChange(of: viewModel.allFoldersLightWallpaper) { _ in viewModel.persistAppearanceOverrides() }

            Picker("Dark Wallpaper", selection: $viewModel.allFoldersDarkWallpaper) {
                Text("None").tag(Optional<String>.none as String?)
                ForEach(viewModel.allFoldersDarkWallpaperImages, id: \.self) { url in
                    Text(url.lastPathComponent).tag(Optional(url.path))
                }
            }
            .disabled(viewModel.isGlobalDarkPinDisabled)
            .onChange(of: viewModel.allFoldersDarkWallpaper) { _ in viewModel.persistAppearanceOverrides() }
        } header: {
            Text("Appearance Overrides")
        } footer: {
            Text("When an appearance theme is set, the wallpaper of that appearance is pinned in the Appearance sheet of the main window.")
        }
    }

    @ViewBuilder
    private var shortcutsPane: some View {
        Section {
            ShortcutRecorder(label: "Show Main Window", shortcut: viewModel.shortcuts.showMain) {
                viewModel.setShowMainShortcut($0)
            }
            ShortcutRecorder(label: "Show Preview", shortcut: viewModel.shortcuts.showPreview) {
                viewModel.setShowPreviewShortcut($0)
            }
            ShortcutRecorder(label: "Open Menu Bar Menu", shortcut: viewModel.shortcuts.showMenu) {
                viewModel.setShowMenuShortcut($0)
            }

            if let errorMessage = viewModel.hotKeyErrorMessage {
                errorRow(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var foldersPane: some View {
        Section {
            if viewModel.folderPaths.isEmpty {
                Text("No folders added yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.folderPaths, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button {
                            viewModel.removeFolder(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Remove folder")
                        .accessibilityLabel("Remove folder \(path)")
                    }
                }
                .onDelete { indexSet in
                    // The settings publish synchronously, so the array shrinks
                    // while the rows are removed. Work on a snapshot.
                    let paths = indexSet.compactMap { index in
                        viewModel.folderPaths.indices.contains(index)
                            ? viewModel.folderPaths[index]
                            : nil
                    }
                    for path in paths {
                        viewModel.removeFolder(path)
                    }
                }
            }

            Button {
                showingAddFolder = true
            } label: {
                Label("Add Folder\u{2026}", systemImage: "plus")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add folder button")
        }
    }

    @ViewBuilder
    private var themesPane: some View {
        Section {
            if viewModel.themes.isEmpty {
                Text("No themes added yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.themes) { theme in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.displayName)
                            Text("Folders: \(theme.folderPaths.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            viewModel.removeTheme(id: theme.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Remove theme")
                        .accessibilityLabel("Remove theme \(theme.displayName)")
                    }
                }
                .onDelete { indexSet in
                    // The settings publish synchronously, so the array shrinks
                    // while the rows are removed. Work on a snapshot.
                    let themes = indexSet.compactMap { index in
                        viewModel.themes.indices.contains(index)
                            ? viewModel.themes[index]
                            : nil
                    }
                    for theme in themes {
                        viewModel.removeTheme(id: theme.id)
                    }
                }
            }

            Button {
                showingAddTheme = true
            } label: {
                Label("Add Theme\u{2026}", systemImage: "plus")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add theme button")
        }
    }

    @ViewBuilder
    private var spacesPane: some View {
        Section {
            if viewModel.allSpaces {
                Text("All Spaces is on. Every Space shows the same wallpaper.")
                    .foregroundStyle(.secondary)
            } else if viewModel.spaces.isEmpty {
                Text("No Spaces reported yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.spaces) { space in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Desktop \(space.index)")
                            Text(space.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if space.isCurrent {
                            Text("Current")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer(minLength: 12)
                        SpaceWallpaperPicker(
                            space: space,
                            images: spacePinImages(for: space),
                            currentWallpaper: viewModel.currentWallpaper.map {
                                URL(fileURLWithPath: $0)
                            },
                            selection: spacePinBinding(space)
                        )
                    }
                }
            }
        } header: {
            Text("Spaces")
        } footer: {
            Text(
                viewModel.allSpaces
                    ? "Turn off All Spaces to keep a wallpaper on one Space."
                    : "A Space follows the current wallpaper until you pin one. New Spaces use the current wallpaper."
            )
        }
        .disabled(viewModel.allSpaces)
    }

    private func spacePinBinding(_ space: DesktopSpace) -> Binding<String?> {
        Binding(
            get: { viewModel.spacePins[space.id] },
            set: { viewModel.setSpacePin($0, for: space.id) }
        )
    }

    /// The images of every folder, plus the pin of the Space even when its
    /// folder is gone: a pin that cannot be shown would look like no pin.
    private func spacePinImages(for space: DesktopSpace) -> [URL] {
        var images = viewModel.allFolderImages
        if let pinned = viewModel.spacePins[space.id],
           !images.contains(where: { $0.path == pinned }) {
            images.append(URL(fileURLWithPath: pinned))
        }
        return images
    }

    @ViewBuilder
    private var rotationPane: some View {
        Section {
            Picker("Interval", selection: $viewModel.intervalMinutes) {
                ForEach(RotationInterval.allCases, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            .accessibilityLabel("Rotation interval picker")
            .disabled(viewModel.isRotationControlDisabled)
            .onChange(of: viewModel.intervalMinutes) { viewModel.setInterval($0) }

            Picker("Action", selection: $viewModel.rotationAction) {
                ForEach(viewModel.availableRotationActions, id: \.self) { action in
                    Text(action.label).tag(action)
                }
            }
            .accessibilityLabel("Rotation action picker")
            .disabled(viewModel.isRotationControlDisabled)
            .onChange(of: viewModel.rotationAction) { viewModel.setRotationAction($0) }
        }
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .textSelection(.enabled)
    }

    /// The toggle runs the registration itself.
    ///
    /// A change handler on the published value would fire again when the
    /// registration writes the status back, so the toggle could clear the
    /// error and spring back without a message.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, spaces, shortcuts, folders, themes, rotation

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .spaces: "rectangle.on.rectangle"
        case .shortcuts: "keyboard"
        case .folders: "folder"
        case .themes: "paintpalette"
        case .rotation: "arrow.triangle.2.circlepath"
        }
    }
}


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

    private let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12"
    ]

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
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
        if event.keyCode == 53 {
            endCapturing()
            onCancel?()
            return nil
        }
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
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }

        var result = ""
        if flags.contains(.control) { result += "\u{2303}" }
        if flags.contains(.option) { result += "\u{2325}" }
        if flags.contains(.shift) { result += "\u{21E7}" }
        if flags.contains(.command) { result += "\u{2318}" }

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
