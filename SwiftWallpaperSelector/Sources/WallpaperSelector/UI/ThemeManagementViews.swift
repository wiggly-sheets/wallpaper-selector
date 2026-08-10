import SwiftUI
import AppKit

// MARK: - Add Folder View

struct AddFolderView: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Folder")
                .font(.headline)

            Button("Choose Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

                if panel.runModal() == .OK, let url = panel.url {
                    onAdd(url.path)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

// MARK: - Edit Folder View

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
                    if FileManager.default.fileExists(atPath: editedFolderPath) {
                        panel.directoryURL = URL(fileURLWithPath: editedFolderPath).deletingLastPathComponent()
                    } else {
                        // Default to home directory if current path invalid
                        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                        if FileManager.default.fileExists(atPath: homeURL.path) {
                            // Check if it's actually a directory
                            var isDir: ObjCBool = false
                            if FileManager.default.fileExists(atPath: homeURL.path, isDirectory: &isDir) && isDir.boolValue {
                                panel.directoryURL = homeURL
                            } else {
                                // Fall back to root of home dir
                                let homeDirURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                                if FileManager.default.fileExists(atPath: homeDirURL.path) {
                                    var isDir2: ObjCBool = false
                                    if FileManager.default.fileExists(atPath: homeDirURL.path, isDirectory: &isDir2) && isDir2.boolValue {
                                        panel.directoryURL = homeDirURL
                                    }
                                }
                            }
                        }

                        if panel.runModal() == .OK, let url = panel.url {
                            editedFolderPath = url.path
                        }
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

// MARK: - Add Theme View

struct AddThemeView: View {
    let onAdd: (Theme) -> Void
    @State private var name = ""
    @State private var folderPaths: [String] = []
    @State private var showingFolderPicker = false
    @State private var selectedFolders: [String] = []
    @State private var lightWallpaper = ""
    @State private var darkWallpaper = ""
    @Environment(\.dismiss) private var dismiss

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
            FolderPickerView(selectedFolders: $selectedFolders)
        }
        .onChange(of: selectedFolders) { newValue in
            folderPaths = newValue
        }
    }

    private func createTheme() {
        let theme = Theme(
            name: name.isEmpty ? "Untitled" : name,
            folderPaths: folderPaths,
            lightWallpaper: lightWallpaper.isEmpty ? nil : lightWallpaper,
            darkWallpaper: darkWallpaper.isEmpty ? nil : darkWallpaper
        )
        onAdd(theme)
        dismiss()
    }
}

// MARK: - Edit Theme View

struct EditThemeView: View {
    let theme: Theme
    let onUpdate: (Theme) -> Void
    @State private var name: String
    @State private var folderPaths: [String]
    @State private var showingFolderPicker = false
    @State private var selectedFolders: [String] = []
    @State private var lightWallpaper: String
    @State private var darkWallpaper: String
    @Environment(\.dismiss) private var dismiss

    init(theme: Theme, onUpdate: @escaping (Theme) -> Void) {
        self.theme = theme
        self.onUpdate = onUpdate
        self._name = State(initialValue: theme.name)
        self._folderPaths = State(initialValue: theme.folderPaths)
        self._selectedFolders = State(initialValue: theme.folderPaths)
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
            FolderPickerView(selectedFolders: $selectedFolders)
        }
        .onChange(of: selectedFolders) { newValue in
            folderPaths = newValue
        }
    }

    private func updateTheme() {
        let updated = Theme(
            name: name.isEmpty ? theme.name : name,
            folderPaths: folderPaths.isEmpty ? theme.folderPaths : folderPaths,
            lightWallpaper: lightWallpaper.isEmpty ? nil : lightWallpaper,
            darkWallpaper: darkWallpaper.isEmpty ? nil : darkWallpaper
        )
        onUpdate(updated)
        dismiss()
    }
}

// MARK: - Folder Picker View

struct FolderPickerView: View {
    @Binding var selectedFolders: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [String] = []
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading folders...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedFolders) {
                        Section(header: Text("Common Locations")) {
                            ForEach(commonFolders, id: \.self) { folder in
                                Label((folder as NSString).lastPathComponent, systemImage: "folder")
                                    .tag(folder)
                            }
                        }

                        Section(header: Text("Other Locations")) {
                            ForEach(userFolders, id: \.self) { folder in
                                Label((folder as NSString).lastPathComponent, systemImage: "folder")
                                    .tag(folder)
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)

                    Spacer()

                    Button("Choose") {
                        selectedFolders = Array(Set(selectedFolders)) // Remove duplicates
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFolders.isEmpty)
                }
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Choose") {
                    selectedFolders = Array(Set(selectedFolders))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolders.isEmpty)
            }
            .padding(.horizontal)
        }
        .frame(width: 350, height: 500)
        .onAppear {
            loadFolders()
        }
    }

    private func loadFolders() {
        isLoading = true
        DispatchQueue.global(qos: .background).async {
            // Common system folders
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let commonPaths = [
                homeDir.path,
                homeDir.appendingPathComponent("Pictures").path,
                homeDir.appendingPathComponent("Desktop").path,
                homeDir.appendingPathComponent("Documents").path,
                "/Users/Shared/Pictures",
                "/Users/Shared/Wallpapers",
                "/Library/Desktop Pictures"
            ].filter { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }

            // User's home folder contents (directories only)
            let allContents = (try? FileManager.default.contentsOfDirectory(
                at: homeDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            let userDirs = allContents.compactMap { url -> String? in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                    return url.path
                }
                return nil
            }

            DispatchQueue.main.async {
                self.commonFolders = commonPaths
                self.userFolders = userDirs
                self.isLoading = false
            }
        }
    }

    @State private var commonFolders: [String] = []
    @State private var userFolders: [String] = []
}
