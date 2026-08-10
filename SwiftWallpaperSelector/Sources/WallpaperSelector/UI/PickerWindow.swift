import SwiftUI
import AppKit

// MARK: - Main Picker Window with Custom Toolbar

struct PickerWindow: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState

    // State for presenting dialogs
    @State private var showingRotationDialog = false
    @State private var showingAppearanceDialog = false
    @State private var showingFoldersDialog = false
    @State private var showingThemesDialog = false

    var body: some View {
        VStack(spacing: 0) {
            // Custom Toolbar
            HStack {
                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(folderTitle)
                        .font(.title3)
                        .fontWeight(.medium)
                    if !settingsViewModel.folderPaths.isEmpty {
                        Text("\(imageCount) images")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Theme Selector
                ThemeSelectorPopup()

                // All Spaces Toggle
                Toggle(isOn: $settingsViewModel.allSpaces) {
                    Label("All Spaces", systemImage: "rectangle.stack")
                        .help("Opens macOS Wallpaper settings — turn on 'Show on all Spaces' there")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: settingsViewModel.allSpaces) { newValue in
                    settingsViewModel.setAllSpaces(newValue)
                    if newValue {
                        // Open macOS Wallpaper settings when All Spaces is enabled
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
                    }
                }

                // Button Group: Previous, Shuffle, Next
                HStack(spacing: 4) {
                    Button(action: { appState.applyPreviousWallpaper() }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!settingsViewModel.hasFolders || appState.isRotationBusy)

                    Button(action: { appState.shuffleWallpaper() }) {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!settingsViewModel.hasFolders || appState.isRotationBusy)

                    Button(action: { appState.applyNextWallpaper() }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!settingsViewModel.hasFolders || appState.isRotationBusy)
                }

                // Rotation... Button
                Button(action: { showingRotationDialog = true }) {
                    Label("Rotation…", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .disabled(settingsViewModel.matchSystemAppearance)

                // Appearance... Button
                Button(action: { showingAppearanceDialog = true }) {
                    Label("Appearance…", systemImage: "circle.lefthalf.filled")
                }
                .buttonStyle(.borderless)

                // Folders... Button
                Button(action: { showingFoldersDialog = true }) {
                    Label("Folders…", systemImage: "folder")
                }
                .buttonStyle(.borderless)

                // Themes... Button
                Button(action: { showingThemesDialog = true }) {
                    Label("Themes…", systemImage: "paintpalette")
                }
                .buttonStyle(.borderless)

                // Settings Button
                Button(action: {
                    // Post notification to open settings window
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: [.command])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .divider()

            // Main Content
            ScrollView {
                VStack(spacing: 0) {
                    if settingsViewModel.folderPaths.isEmpty {
                        // Empty state: no folders
                        VStack(spacing: 16) {
                            Image(systemName: "folder")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Choose wallpaper folders")
                                .font(.title2)
                            Text("Add folders containing images to set as your wallpaper.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            Button(action: { showingFoldersDialog = true }) {
                                Label("Choose Folders", systemImage: "plus.folder")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if appState.currentThemeImages.isEmpty {
                        // Empty state: theme has no images
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("This theme has no images")
                                .font(.title2)
                            Text("Add folders with supported image formats (.png, .jpg, .jpeg, .webp) to this theme.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            Button(action: { showingThemesDialog = true }) {
                                Label("Edit Theme", systemImage: "paintpalette")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        // Grid of thumbnails
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                            ForEach(appState.currentThemeImages, id: \.self) { url in
                                WallpaperThumbnail(imageURL: url)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        ZStack {
                                            if appState.isCurrentWallpaper(url.path) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(Color.accentColor, lineWidth: 2)
                                                VStack {
                                                    HStack {
                                                        Spacer()
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.title3)
                                                            .foregroundColor(Color.accentColor)
                                                            .background(Circle().fill(Color.white))
                                                            .padding(4)
                                                    }
                                                    Spacer()
                                                }
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        appState.setWallpaper(url)
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 640)
        .sheet(isPresented: $showingRotationDialog) {
            RotationDialog()
                .environmentObject(settingsViewModel)
                .environmentObject(appState)
                .frame(width: 360, height: 300)
        }
        .sheet(isPresented: $showingAppearanceDialog) {
            AppearanceDialog()
                .environmentObject(settingsViewModel)
                .environmentObject(appState)
                .frame(width: 420, height: 400)
        }
        .sheet(isPresented: $showingFoldersDialog) {
            FoldersDialog()
                .environmentObject(settingsViewModel)
                .frame(width: 400, height: 300)
        }
        .sheet(isPresented: $showingThemesDialog) {
            ThemesDialog()
                .environmentObject(settingsViewModel)
                .frame(width: 440, height: 400)
        }
    }

    // MARK: - Computed Properties

    private var folderTitle: String {
        let folders = settingsViewModel.folderPaths
        if folders.isEmpty {
            return "Wallpaper Selector"
        } else if folders.count == 1 {
            return (folders.first! as NSString).lastPathComponent
        } else {
            return "\(folders.count) folders"
        }
    }

    private var imageCount: Int {
        appState.currentThemeImages.count
    }
}

// MARK: - Supporting Views

struct ThemeSelectorPopup: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu {
            Button(action: {
                appState.setActiveTheme(nil)
            }) {
                Label("All Folders", systemImage: "folder")
                    .foregroundColor(.primary)
            }
            .keyboardShortcut("0", modifiers: [.command])

            Divider()

            ForEach(settingsViewModel.themes) { theme in
                Button(action: {
                    appState.setActiveTheme(theme.id)
                }) {
                    HStack {
                        Text(theme.displayName)
                        Spacer()
                        if theme.id == settingsViewModel.activeThemeID {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        } label: {
            Label(settingsViewModel.activeThemeID == nil ? "All Folders" : (settingsViewModel.themes.first { $0.id == settingsViewModel.activeThemeID }?.displayName ?? "Theme"), systemImage: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct WallpaperThumbnail: View {
    let imageURL: URL

    @State private var nsImage: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: 100, height: 100)
            } else if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
            } else {
                Color.secondary.opacity(0.1)
                    .frame(width: 100, height: 100)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var image: NSImage?
            if let data = try? Data(contentsOf: imageURL) {
                image = NSImage(data: data)
            }
            DispatchQueue.main.async {
                self.nsImage = image
                self.isLoading = false
            }
        }
    }
}

// MARK: - Dialogs

struct RotationDialog: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Automatic Rotation")
                .font(.headline)

            Text(settingsViewModel.matchSystemAppearance ?
                 "Paused while Match System Appearance is on (see Appearance…)." :
                 "Change the wallpaper on its own, on a schedule you choose.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Interval")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Interval", selection: $settingsViewModel.intervalMinutes) {
                    ForEach(RotationInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .disabled(settingsViewModel.matchSystemAppearance)
                .onChange(of: settingsViewModel.intervalMinutes) { settingsViewModel.setInterval($0) }

                Text("On Interval:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                Picker("Action", selection: $settingsViewModel.rotationAction) {
                    // Wallpaper actions
                    Group {
                        Text("Shuffle Wallpaper").tag(RotationAction.shuffle)
                        Text("Next Wallpaper").tag(RotationAction.next)
                        Text("Previous Wallpaper").tag(RotationAction.previous)
                    }
                    .divider()
                    // Theme actions
                    Group {
                        Text("Shuffle Theme").tag(RotationAction.themeShuffle)
                        Text("Next Theme").tag(RotationAction.themeNext)
                        Text("Previous Theme").tag(RotationAction.themePrevious)
                    }
                    .disabled(settingsViewModel.themes.isEmpty)
                }
                .pickerStyle(.menu)
                .disabled(settingsViewModel.intervalMinutes == .off || settingsViewModel.matchSystemAppearance)
                .onChange(of: settingsViewModel.rotationAction) { settingsViewModel.setRotationAction($0) }
            }
            .padding(.horizontal)

            Button(action: {
                // Apply settings and restart rotation
                appState.updateRotationSettings()
                dismiss()
            }) {
                Text("OK")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct AppearanceDialog: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var lightThemeID: String?
    @State private var darkThemeID: String?
    @State private var lightWallpaper: String?
    @State private var darkWallpaper: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Light & Dark Wallpaper")
                .font(.headline)

            let themeName = settingsViewModel.activeThemeID == nil ?
                "All Folders" :
                (settingsViewModel.themes.first { $0.id == settingsViewModel.activeThemeID }?.name ?? "Theme")
            Text("Applies while \"\(themeName)\" is the active theme.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Toggle(isOn: $settingsViewModel.matchSystemAppearance) {
                Label("Match System Appearance", systemImage: "circle.lefthalf.filled")
            }
            .toggleStyle(.switch)
            .onChange(of: settingsViewModel.matchSystemAppearance) { newValue in
                settingsViewModel.setMatchSystemAppearance(newValue)
                if newValue {
                    appState.applyAppearanceWallpaperIfNeeded()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                    Text("Light Theme")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Light Theme", selection: $lightThemeID) {
                        Text("None").tag(Optional<String>.none as String?)
                        ForEach(settingsViewModel.themes) { theme in
                            Text(theme.name).tag(Optional(theme.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Dark Theme")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Dark Theme", selection: $darkThemeID) {
                        Text("None").tag(Optional<String>.none as String?)
                        ForEach(settingsViewModel.themes) { theme in
                            Text(theme.name).tag(Optional(theme.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Divider()

                    Text("Optionally pin an exact image within the current theme below.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Light Wallpaper")
                        Spacer()
                        Menu {
                            ForEach(appState.currentThemeImages, id: \.self) { url in
                                Button(action: { lightWallpaper = url.path }) {
                                    Text(url.lastPathComponent)
                                }
                            }
                        } label: {
                            Text(lightWallpaper == nil ? "None" : (lightWallpaper! as NSString).lastPathComponent)
                                .frame(minWidth: 120, alignment: .trailing)
                        }
                    }

                    HStack {
                        Text("Dark Wallpaper")
                        Spacer()
                        Menu {
                            ForEach(appState.currentThemeImages, id: \.self) { url in
                                Button(action: { darkWallpaper = url.path }) {
                                    Text(url.lastPathComponent)
                                }
                            }
                        } label: {
                            Text(darkWallpaper == nil ? "None" : (darkWallpaper! as NSString).lastPathComponent)
                                .frame(minWidth: 120, alignment: .trailing)
                        }
                    }
            }
            .padding(.horizontal)

            Button(action: {
                // Save appearance settings
                settingsViewModel.setAppearanceOverrides(
                    lightThemeID: lightThemeID,
                    darkThemeID: darkThemeID,
                    lightWallpaper: lightWallpaper,
                    darkWallpaper: darkWallpaper
                )
                appState.applyAppearanceWallpaperIfNeeded()
                dismiss()
            }) {
                Text("OK")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            // Initialize form values
            lightThemeID = settingsViewModel.appearanceLightThemeID
            darkThemeID = settingsViewModel.appearanceDarkThemeID
            lightWallpaper = settingsViewModel.allFoldersLightWallpaper
            darkWallpaper = settingsViewModel.allFoldersDarkWallpaper
        }
    }
}

struct FoldersDialog: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddFolder = false
    @State private var showingEditFolder = false
    @State private var folderToEdit: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Folders")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddFolder = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            List {
                ForEach(settingsViewModel.folderPaths, id: \.self) { path in
                    HStack {
                        Text((path as NSString).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(action: {
                            folderToEdit = path
                            showingEditFolder = true
                        }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit folder")

                        Button(action: {
                            settingsViewModel.removeFolder(path)
                        }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            Button(action: {
                dismiss()
            }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 400, height: 300)
        .sheet(isPresented: $showingAddFolder) {
            AddFolderView { path in
                settingsViewModel.addFolder(path)
            }
        }
        .sheet(isPresented: $showingEditFolder, onDismiss: { folderToEdit = nil }) {
            if let folderToEdit = folderToEdit {
                EditFolderView(
                    folderPath: folderToEdit,
                    onUpdate: { newPath in
                        // For edit, we just update the folder path (remove old, add new)
                        settingsViewModel.removeFolder(folderToEdit)
                        settingsViewModel.addFolder(newPath)
                    }
                )
            }
        }
    }
}

struct ThemesDialog: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddTheme = false
    @State private var selectedThemeID: String?
    @State private var themeToDelete: String? = nil
    @State private var showingDeleteAlert = false
    @State private var themeToEdit: Theme? = nil
    @State private var showingEditTheme = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Themes")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddTheme = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            List {
                Section(header: Text("All Folders")) {
                    Button(action: {
                        selectedThemeID = nil
                    }) {
                        HStack {
                            Text("All Folders")
                            Spacer()
                            if selectedThemeID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }

                Section(header: Text("Themes")) {
                    ForEach(settingsViewModel.themes) { theme in
                        HStack {
                            Button {
                                selectedThemeID = theme.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(theme.name)
                                            .font(.body)
                                        if !theme.folderPaths.isEmpty {
                                            Text(theme.folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("No folders")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedThemeID == theme.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                themeToEdit = theme
                                showingEditTheme = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Edit theme")

                            Button {
                                themeToDelete = theme.id
                                showingDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .listStyle(.sidebar)

            Button(action: {
                settingsViewModel.setActiveTheme(selectedThemeID)
                dismiss()
            }) {
                Text("Apply")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 440, height: 400)
        .sheet(isPresented: $showingAddTheme) {
            AddThemeView { theme in
                settingsViewModel.addTheme(theme)
            }
        }
        .sheet(isPresented: $showingEditTheme, onDismiss: { themeToEdit = nil }) {
            if let theme = themeToEdit {
                EditThemeView(theme: theme) { updated in
                    settingsViewModel.editTheme(
                        id: theme.id,
                        name: updated.name,
                        folderPaths: updated.folderPaths,
                        lightWallpaper: updated.lightWallpaper,
                        darkWallpaper: updated.darkWallpaper
                    )
                }
            }
        }
        .alert("Delete Theme?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = themeToDelete {
                    settingsViewModel.removeTheme(id: id)
                }
            }
        } message: {
            if let id = themeToDelete,
               let theme = settingsViewModel.themes.first(where: { $0.id == id }) {
                Text("Are you sure you want to delete the theme \"\(theme.name)\"?")
            } else {
                Text("Are you sure you want to delete this theme?")
            }
        }
        .onAppear {
            selectedThemeID = settingsViewModel.activeThemeID
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
}

extension View {
    func divider() -> some View {
        self.background(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }
}
