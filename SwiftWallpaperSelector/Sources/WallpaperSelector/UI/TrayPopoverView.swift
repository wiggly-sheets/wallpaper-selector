import SwiftUI
import AppKit

struct TrayPopoverView: View {
    @EnvironmentObject var viewModel: TrayPopoverViewModel

    var body: some View {
        VStack(spacing: 10) {
            headerView
            themeSelector
            shuffleControls
            gridView
            Divider()
            autoRotateSection
            allSpacesSection
        }
        .padding(8)
        .frame(width: 300, height: 528)
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
            rotateButton("←", enabled: shuffleEnabled, action: viewModel.previous)
            rotateButton("↺", enabled: shuffleEnabled, action: viewModel.shuffle)
            rotateButton("→", enabled: shuffleEnabled, action: viewModel.next)
        }
        .frame(maxWidth: .infinity)
    }

    private var shuffleEnabled: Bool {
        !viewModel.images.isEmpty && !viewModel.isBusy
    }


    private var gridView: some View {
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
                }
            }
            .padding(8)
        }
        .frame(maxHeight: .infinity)
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
                .frame(maxWidth: .infinity)

                Spacer()

                HStack(spacing: 2) {
                    rotateButton("←", enabled: autoEnabled, action: viewModel.previous)
                    rotateButton("↺", enabled: autoEnabled, action: viewModel.shuffle)
                    rotateButton("→", enabled: autoEnabled, action: viewModel.next)
                    Divider().frame(height: 16)
                    rotateButton("≪", enabled: themeAutoEnabled, action: viewModel.themePrevious)
                    rotateButton("◊", enabled: themeAutoEnabled, action: viewModel.themeShuffle)
                    rotateButton("≫", enabled: themeAutoEnabled, action: viewModel.themeNext)
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

    private var autoEnabled: Bool {
        viewModel.intervalMinutes != .off && shuffleEnabled
    }

    private var themeAutoEnabled: Bool {
        viewModel.intervalMinutes != .off && !viewModel.themes.isEmpty
    }


    private var allSpacesSection: some View {
        Toggle(isOn: allSpacesBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All Spaces")
                Text("Show the wallpaper on every desktop")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var allSpacesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.allSpaces },
            set: { viewModel.setAllSpaces($0) }
        )
    }


    private func rotateButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}


struct TrayPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        let settingsManager = SettingsManager()
        let wallpaperProvider = WallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)

        let rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )

        return TrayPopoverView()
            .environmentObject(TrayPopoverViewModel(
                settingsManager: settingsManager,
                wallpaperProvider: wallpaperProvider,
                themeProvider: themeProvider,
                rotationService: rotationService
            ))
            .frame(width: 300, height: 528)
    }
}
