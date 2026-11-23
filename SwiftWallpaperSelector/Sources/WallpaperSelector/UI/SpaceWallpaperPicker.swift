import SwiftUI
import AppKit

/// The wallpaper picker of one Space.
///
/// A menu shows the name of an image and nothing else, and a Space is easier
/// to recognize by its picture. The picker opens a grid of previews instead.
struct SpaceWallpaperPicker: View {
    let space: DesktopSpace
    let images: [URL]
    let currentWallpaper: URL?
    @Binding var selection: String?

    @State private var isPresented = false

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 12)]

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                if let selected = selectedImage {
                    SpacePickerThumbnail(imageURL: selected)
                        .frame(width: 30, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(selectedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Wallpaper for Desktop \(space.index)")
        .accessibilityValue(selectedName)
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Wallpaper for Desktop \(space.index)")
                    .font(.headline)
                    .padding([.horizontal, .top], 16)
                    .padding(.bottom, 10)

                Divider()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        wallpaperTile(
                            title: "Use Current Wallpaper",
                            url: currentWallpaper,
                            isSelected: selection == nil,
                            systemImage: "arrow.triangle.2.circlepath"
                        ) {
                            selection = nil
                            isPresented = false
                        }
                        ForEach(images, id: \.self) { url in
                            wallpaperTile(
                                title: url.deletingPathExtension().lastPathComponent,
                                url: url,
                                isSelected: selection == url.path,
                                systemImage: nil
                            ) {
                                selection = url.path
                                isPresented = false
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .frame(width: 560, height: 420)
        }
    }

    private var selectedImage: URL? {
        guard let selection else { return nil }
        let url = URL(fileURLWithPath: selection)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var selectedName: String {
        guard let selection else { return "Use Current Wallpaper" }
        return URL(fileURLWithPath: selection).deletingPathExtension().lastPathComponent
    }

    private func wallpaperTile(
        title: String,
        url: URL?,
        isSelected: Bool,
        systemImage: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let url {
                            SpacePickerThumbnail(imageURL: url)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: systemImage ?? "photo")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 132, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(5)
                    }
                }

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A preview that fills its frame, for the grid of the picker.
private struct SpacePickerThumbnail: View {
    let imageURL: URL

    @State private var nsImage: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            } else {
                Color.secondary.opacity(0.12)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .clipped()
        .task(id: imageURL) {
            isLoading = true
            let thumbnail = await WallpaperThumbnailRepository.shared.thumbnail(
                for: imageURL,
                maximumPixelSize: 320
            )
            guard !Task.isCancelled else { return }
            nsImage = thumbnail.map { NSImage(cgImage: $0.image, size: .zero) }
            isLoading = false
        }
    }
}
