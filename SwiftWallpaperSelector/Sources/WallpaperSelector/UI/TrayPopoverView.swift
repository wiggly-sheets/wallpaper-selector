import SwiftUI
import AppKit

// shortcut: the enabled state lives in the view model and is tested there, but no test can see whether this binding is negated, upgrade when a UI test harness exists
struct TrayPopoverView: View {
    @EnvironmentObject var viewModel: TrayPopoverViewModel

    var body: some View {
        // The body scrolls, so a popover that is clamped to a short
        // display can still reach every control. The height of the popover
        // is the height of the content.
        ScrollView {
            VStack(spacing: 10) {
                headerView
                themeSelector
                shuffleControls
                gridView
                Divider()
                autoRotateSection
                allSpacesSection
                errorCaption
            }
            .padding(8)
        }
        .frame(width: 300)
        .onAppear {
            // Files can be added or removed while the popover is closed.
            viewModel.refreshImagesFromDisk()
        }
    }


    private var errorCaption: some View {
        Group {
            if let errorMessage = viewModel.lastError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }


    private var headerView: some View {
        HStack(spacing: 8) {
            Text(viewModel.foldersTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: viewModel.openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)

            Button(action: viewModel.showMainWindow) {
                Text("Open")
            }
            .buttonStyle(.borderless)
        }
    }


    private var themeSelector: some View {
        Menu {
            Button(action: { viewModel.selectTheme(nil) }) {
                Label("All Folders", systemImage: "folder")
            }
            Divider()
            ForEach(viewModel.themes) { theme in
                Button(action: { viewModel.selectTheme(theme.id) }) {
                    HStack {
                        Text(theme.displayName)
                        Spacer()
                        if theme.id == viewModel.activeThemeID {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        } label: {
            Label(
                viewModel.activeThemeID == nil
                    ? "All Folders"
                    : (viewModel.themes.first { $0.id == viewModel.activeThemeID }?.displayName ?? "Theme"),
                systemImage: "paintpalette"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }


    private var shuffleControls: some View {
        HStack(spacing: 4) {
            rotateButton("←", label: "Previous wallpaper", enabled: shuffleEnabled, action: viewModel.previous)
            rotateButton("↺", label: "Shuffle wallpaper", enabled: shuffleEnabled, action: viewModel.shuffle)
            rotateButton("→", label: "Next wallpaper", enabled: shuffleEnabled, action: viewModel.next)
        }
        .frame(maxWidth: .infinity)
    }

    private var shuffleEnabled: Bool {
        !viewModel.images.isEmpty && !viewModel.isBusy
    }


    private var gridView: some View {
        // The grid scrolls in its own area, so a long list of wallpapers
        // does not make the popover taller than it has to be.
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                ForEach(viewModel.images, id: \.self) { url in
                    WallpaperThumbnail(imageURL: url)
                        .overlay(alignment: .bottomTrailing) {
                            if url.path == viewModel.currentWallpaperPath {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                    .padding(4)
                            }
                        }
                        .onTapGesture {
                            viewModel.selectWallpaper(url)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(url.lastPathComponent)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(
                            url.path == viewModel.currentWallpaperPath
                                ? .isSelected
                                : AccessibilityTraits()
                        )
                        .accessibilityAction {
                            viewModel.selectWallpaper(url)
                        }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 280)
    }


    private var autoRotateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Auto-Rotate")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Picker("Interval", selection: intervalBinding) {
                    ForEach(RotationInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                // The rotation cannot run while the appearance is matched.
                .disabled(viewModel.isRotationControlDisabled)
                .frame(maxWidth: .infinity)

                Spacer()

                // The wallpaper controls are in the top row. This row holds
                // the theme controls only.
                HStack(spacing: 2) {
                    rotateButton("≪", label: "Previous theme", enabled: viewModel.isThemeActionEnabled, action: viewModel.themePrevious)
                    rotateButton("◊", label: "Shuffle theme", enabled: viewModel.isThemeActionEnabled, action: viewModel.themeShuffle)
                    rotateButton("≫", label: "Next theme", enabled: viewModel.isThemeActionEnabled, action: viewModel.themeNext)
                }
            }
        }
    }

    private var intervalBinding: Binding<RotationInterval> {
        Binding(
            get: { viewModel.intervalMinutes },
            set: { viewModel.setInterval($0) }
        )
    }


    private var allSpacesSection: some View {
        Toggle(isOn: allSpacesBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All Spaces")
                Text("Put the wallpaper on every Space")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        // The toggle can always be turned off: a setting that was stored on
        // a newer macOS must be clearable here.
        .disabled(!AllSpacesSupport.isAvailable && !viewModel.allSpaces)
        .help(AllSpacesSupport.isAvailable
              ? "Puts the wallpaper on every Space"
              : "Needs macOS 14 or newer.")
    }

    private var allSpacesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.allSpaces },
            set: { viewModel.setAllSpaces($0) }
        )
    }


    private func rotateButton(_ title: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}


struct TrayPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        // The preview must not touch the settings of the user: the manager
        // writes a settings file and can import the legacy file of the
        // Electron version. The preview uses a folder of its own.
        let previewDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperSelectorPreview", isDirectory: true)
        let settingsManager = SettingsManager(
            settingsDirectory: previewDirectory,
            migrateLegacySettings: false
        )
        let wallpaperProvider = WallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)

        let rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider
        )

        return TrayPopoverView()
            .environmentObject(TrayPopoverViewModel(appState: appState))
            .frame(width: 300)
    }
}
