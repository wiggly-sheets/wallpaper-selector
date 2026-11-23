import SwiftUI
import AppKit


struct AddFolderView: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPaths: Set<String> = []

    private let suggestions: [SuggestedFolder]

    init(onAdd: @escaping (String) -> Void) {
        self.onAdd = onAdd
        suggestions = SuggestedFolder.standard
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Folders")
                    .font(.headline)
                Text("Select folders that contain images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            if suggestions.isEmpty {
                Text("No suggested folders were found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(suggestions) { folder in
                    Toggle(isOn: selectionBinding(for: folder.path)) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Browse\u{2026}", action: browse)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    for path in selectedPaths.sorted() {
                        onAdd(path)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPaths.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 340)
    }

    private func selectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectedPaths.insert(path)
                } else {
                    selectedPaths.remove(path)
                }
            }
        )
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK {
            for url in panel.urls {
                onAdd(url.path)
            }
            dismiss()
        }
    }
}

private struct SuggestedFolder: Identifiable {
    let name: String
    let path: String

    var id: String { path }

    /// The picture folders a new user is likely to keep wallpapers in.
    static var standard: [SuggestedFolder] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            (name: "Wallpapers", path: home + "/Pictures/Wallpapers"),
            (name: "Pictures", path: home + "/Pictures"),
            (name: "Downloads", path: home + "/Downloads"),
            (name: "Desktop", path: home + "/Desktop")
        ]
        var isDirectory: ObjCBool = false
        return candidates.compactMap { candidate in
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return SuggestedFolder(name: candidate.name, path: candidate.path)
        }
    }
}


struct EditFolderView: View {
    let folderPath: String
    let onUpdate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editedFolderPath: String

    init(folderPath: String, onUpdate: @escaping (String) -> Void) {
        self.folderPath = folderPath
        self.onUpdate = onUpdate
        _editedFolderPath = State(initialValue: folderPath)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Folder")
                .font(.headline)

            HStack {
                TextField("Folder Path", text: $editedFolderPath)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

                Button("Choose...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false

                    let currentURL = URL(fileURLWithPath: editedFolderPath, isDirectory: true)
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(
                        atPath: editedFolderPath,
                        isDirectory: &isDirectory
                    ), isDirectory.boolValue {
                        panel.directoryURL = currentURL.deletingLastPathComponent()
                    } else {
                        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                    }

                    if panel.runModal() == .OK, let url = panel.url {
                        editedFolderPath = url.path
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Update") {
                    onUpdate(editedFolderPath)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 150)
    }
}


struct AddThemeView: View {
    let availableFolders: [String]
    let onAdd: (Theme) -> Void
    @State private var name = ""
    @State private var folderPaths: [String] = []
    @State private var showingFolderPicker = false
    @State private var lightWallpaper = ""
    @State private var darkWallpaper = ""
    @Environment(\.dismiss) private var dismiss

    init(availableFolders: [String], onAdd: @escaping (Theme) -> Void) {
        self.availableFolders = orderedUniquePaths(availableFolders)
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Theme")
                .font(.headline)

            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Name", text: $name)
                }

                Section(header: Text("Folders")) {
                    VStack(alignment: .leading) {
                        Text("Selected folders: \(folderPaths.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Choose Folders...") {
                            showingFolderPicker = true
                        }
                    }
                }

                Section(header: Text("Wallpapers")) {
                    HStack {
                        Text("Light:")
                        Spacer()
                        TextField("Path", text: $lightWallpaper)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }

                    HStack {
                        Text("Dark:")
                        Spacer()
                        TextField("Path", text: $darkWallpaper)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    createTheme()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || folderPaths.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(
                selectedFolders: $folderPaths,
                availableFolders: availableFolders
            )
        }
    }

    private func createTheme() {
        let theme = Theme(
            name: name.isEmpty ? "Untitled" : name,
            folderPaths: folderPaths,
            lightWallpaper: optionalPath(lightWallpaper),
            darkWallpaper: optionalPath(darkWallpaper)
        )
        onAdd(theme)
        dismiss()
    }
}


struct EditThemeView: View {
    let theme: Theme
    let availableFolders: [String]
    let onUpdate: (Theme) -> Void
    @State private var name: String
    @State private var folderPaths: [String]
    @State private var showingFolderPicker = false
    @State private var lightWallpaper: String
    @State private var darkWallpaper: String
    @Environment(\.dismiss) private var dismiss

    init(
        theme: Theme,
        availableFolders: [String],
        onUpdate: @escaping (Theme) -> Void
    ) {
        let orderedFolders = orderedUniquePaths(availableFolders)
        let availableFolderSet = Set(orderedFolders)
        let validThemeFolders = orderedUniquePaths(
            theme.folderPaths.filter { availableFolderSet.contains($0) }
        )

        self.theme = theme
        self.availableFolders = orderedFolders
        self.onUpdate = onUpdate
        self._name = State(initialValue: theme.name)
        self._folderPaths = State(initialValue: validThemeFolders)
        self._lightWallpaper = State(initialValue: theme.lightWallpaper ?? "")
        self._darkWallpaper = State(initialValue: theme.darkWallpaper ?? "")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Theme")
                .font(.headline)

            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Name", text: $name)
                }

                Section(header: Text("Folders")) {
                    VStack(alignment: .leading) {
                        Text("Selected folders: \(folderPaths.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Choose Folders...") {
                            showingFolderPicker = true
                        }
                    }
                }

                Section(header: Text("Wallpapers")) {
                    HStack {
                        Text("Light:")
                        Spacer()
                        TextField("Path", text: $lightWallpaper)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }

                    HStack {
                        Text("Dark:")
                        Spacer()
                        TextField("Path", text: $darkWallpaper)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Update") {
                    updateTheme()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || folderPaths.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(
                selectedFolders: $folderPaths,
                availableFolders: availableFolders
            )
        }
    }

    private func updateTheme() {
        let updated = Theme(
            id: theme.id,
            name: name.isEmpty ? theme.name : name,
            folderPaths: folderPaths,
            lightWallpaper: optionalPath(lightWallpaper),
            darkWallpaper: optionalPath(darkWallpaper)
        )
        onUpdate(updated)
        dismiss()
    }
}


struct FolderPickerView: View {
    @Binding var selectedFolders: [String]
    let availableFolders: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: Set<String>

    init(selectedFolders: Binding<[String]>, availableFolders: [String]) {
        let orderedFolders = orderedUniquePaths(availableFolders)
        let availableFolderSet = Set(orderedFolders)

        self._selectedFolders = selectedFolders
        self.availableFolders = orderedFolders
        self._draftSelection = State(
            initialValue: Set(selectedFolders.wrappedValue).intersection(availableFolderSet)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose Folders")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            Divider()

            if availableFolders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No configured folders")
                        .font(.headline)
                    Text("Add a wallpaper folder before creating a Theme.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(availableFolders, id: \.self) { folder in
                        Toggle(isOn: selectionBinding(for: folder)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(
                                    (folder as NSString).lastPathComponent,
                                    systemImage: "folder"
                                )
                                Text(folder)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Choose") {
                    selectedFolders = availableFolders.filter { draftSelection.contains($0) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draftSelection.isEmpty)
            }
            .padding()
        }
        .frame(width: 350, height: 500)
    }

    private func selectionBinding(for folder: String) -> Binding<Bool> {
        Binding(
            get: { draftSelection.contains(folder) },
            set: { isSelected in
                if isSelected {
                    draftSelection.insert(folder)
                } else {
                    draftSelection.remove(folder)
                }
            }
        )
    }
}

private func orderedUniquePaths(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.filter { seen.insert($0).inserted }
}

private func optionalPath(_ path: String) -> String? {
    path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : path
}
