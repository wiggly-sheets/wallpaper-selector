import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Wallpaper Selector")
                .font(.title2)
                .fontWeight(.bold)

            // Status
            Text("Folders: \(settingsManager.settings.folderPaths.count)")
            Text("Themes: \(settingsManager.settings.themes.count)")
            Text("Rotation: \(settingsManager.settings.intervalMinutes.label)")
            Text("All Spaces: \(settingsManager.settings.allSpaces ? "On" : "Off")")
            Text("Match Appearance: \(settingsManager.settings.matchSystemAppearance ? "On" : "Off")")

            Divider()

            // Rotation controls
            HStack {
                Text("Interval:")
                Picker("Interval", selection: Binding(
                    get: { settingsManager.settings.intervalMinutes },
                    set: { val in settingsManager.update { $0.intervalMinutes = val } }
                )) {
                    ForEach(RotationInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Wallpaper rotation interval picker")

                Text("Action:")
                Picker("Action", selection: Binding(
                    get: { settingsManager.settings.rotationAction },
                    set: { val in settingsManager.update { $0.rotationAction = val } }
                )) {
                    ForEach(RotationAction.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Wallpaper rotation action picker")
            }

            // Appearance controls
            Toggle("Match System Appearance", isOn: Binding(
                get: { settingsManager.settings.matchSystemAppearance },
                set: { val in settingsManager.update { $0.matchSystemAppearance = val } }
            ))
            .accessibilityLabel("Match system appearance toggle")

            // All Spaces
            Toggle("All Spaces", isOn: Binding(
                get: { settingsManager.settings.allSpaces },
                set: { val in settingsManager.update { $0.allSpaces = val } }
            ))
            .accessibilityLabel("All spaces toggle")

            // History limit
            HStack {
                Text("History Limit:")
                Picker("History Limit", selection: Binding(
                    get: { settingsManager.settings.historyLimit },
                    set: { val in settingsManager.update { $0.historyLimit = val } }
                )) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("History limit picker")
            }

            Divider()

            // Buttons
            HStack {
                Button("Shuffle") {
                    settingsManager.update { $0.rotationAction = .shuffle }
                }
                .accessibilityLabel("Shuffle wallpaper button")
                Button("Next") {
                    settingsManager.update { $0.rotationAction = .next }
                }
                .accessibilityLabel("Next wallpaper button")
                Button("Previous") {
                    settingsManager.update { $0.rotationAction = .previous }
                }
                .accessibilityLabel("Previous wallpaper button")
            }

            Button("Open Settings") {
                showingSettings = true
            }
            .accessibilityLabel("Open settings button")
        }
        .padding()
        .frame(width: 480, height: 360)
    }
}