import SwiftUI

/// The browser for the wallpapers a source offers right now.
///
/// One gesture downloads a wallpaper and puts it on the screen, so browsing
/// and picking stay together. A downloaded wallpaper lands in the download
/// folder, which joins the rotation like any folder the user adds.
struct RemoteWallpaperBrowser: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Browse Online Wallpapers")
                    .font(.headline)

                Spacer()

                if !settingsViewModel.wallpaperSources.isEmpty {
                    Picker("Source", selection: $settingsViewModel.remoteBrowserSource) {
                        ForEach(settingsViewModel.wallpaperSources) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    .onChange(of: settingsViewModel.remoteBrowserSource) { _ in
                        settingsViewModel.loadRemoteWallpapers()
                    }
                }

                Button {
                    settingsViewModel.loadRemoteWallpapers()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(settingsViewModel.wallpaperSources.isEmpty
                          || settingsViewModel.isLoadingRemoteWallpapers)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .divider()

            content
        }
        .frame(width: 760, height: 540)
        .onAppear {
            // The list is loaded again when the sheet opens: the source may
            // offer other wallpapers by then.
            settingsViewModel.loadRemoteWallpapers()
        }
    }

    @ViewBuilder
    private var content: some View {
        if settingsViewModel.wallpaperSources.isEmpty {
            message("Check a source in Settings \u{203A} Sources to browse it here.")
        } else if settingsViewModel.isLoadingRemoteWallpapers && settingsViewModel.remoteWallpapers.isEmpty {
            ProgressView("Loading wallpapers\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if settingsViewModel.remoteWallpapers.isEmpty {
            message("No wallpapers found. Try Refresh.")
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(settingsViewModel.remoteWallpapers) { wallpaper in
                        tile(wallpaper)
                    }
                }
                .padding()
            }
        }

        if let errorMessage = settingsViewModel.remoteWallpaperError {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .bottom])
        }
    }

    private func tile(_ wallpaper: RemoteWallpaper) -> some View {
        let isApplied = settingsViewModel.appliedRemoteWallpaperPath
            == settingsViewModel.wallpapersDownloadFolder
                .appendingPathComponent(wallpaper.fileName)
                .path
        let isApplying = settingsViewModel.applyingRemoteWallpaper == wallpaper.fileName

        return VStack(spacing: 4) {
            AsyncImage(url: wallpaper.thumbnailURL ?? wallpaper.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                default:
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 160, height: 90)
            .clipped()
            .overlay {
                if isApplied {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .padding(4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(wallpaper.fileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settingsViewModel.useRemoteWallpaper(wallpaper)
        }
        .help("Download and set \(wallpaper.fileName)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wallpaper.fileName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isApplied ? .isSelected : AccessibilityTraits())
        .accessibilityAction {
            settingsViewModel.useRemoteWallpaper(wallpaper)
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
