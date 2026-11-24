import Foundation

/// The rule that decides whether the automatic download runs today.
///
/// It is a pure function, so a test can ask for any day.
enum DailyDownloadSchedule {
    static func day(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isDue(
        enabled: Bool,
        sources: [WallpaperSource],
        lastDay: String?,
        now: Date = Date()
    ) -> Bool {
        guard enabled, !sources.isEmpty else { return false }
        return lastDay != day(for: now)
    }
}

/// Downloads the selected sources once a day while the app runs.
///
/// The day of the last download is stored in the settings, so a restart does
/// not download a second time. The check runs on a timer, so a Mac that
/// wakes up after midnight downloads on its own.
@MainActor
final class DailyDownloadService {
    private let settingsManager: SettingsManager
    private let appState: AppState
    private let reportError: (String) -> Void
    private let service: WallpaperDownloadService
    private var timer: Timer?
    private var isDownloading = false

    /// A Mac can sleep through the moment the day changes, so the check is
    /// repeated instead of being planned for midnight.
    private static let checkInterval: TimeInterval = 30 * 60
    private static let wallpapersPerSource = 3

    init(
        settingsManager: SettingsManager,
        appState: AppState,
        reportError: @escaping (String) -> Void,
        service: WallpaperDownloadService = WallpaperDownloadService()
    ) {
        self.settingsManager = settingsManager
        self.appState = appState
        self.reportError = reportError
        self.service = service
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }

    func checkNow() {
        let settings = settingsManager.settings
        guard DailyDownloadSchedule.isDue(
            enabled: settings.dailyDownloadEnabled,
            sources: settings.wallpaperSources,
            lastDay: settings.lastDailyDownloadDay
        ) else { return }
        guard !isDownloading else { return }

        isDownloading = true
        let sources = settings.wallpaperSources
        let folder = WallpaperDownloadFolder.url
        let day = DailyDownloadSchedule.day(for: Date())

        Task { [weak self, service] in
            let summary = await service.downloadWallpapers(
                from: sources,
                count: Self.wallpapersPerSource,
                into: folder
            )
            guard let self else { return }
            self.isDownloading = false
            // The day is recorded even when the download failed: a source
            // that is down is not asked again every half hour. The failure is
            // reported through the wallpaper error channel instead.
            self.settingsManager.update { settings in
                settings.lastDailyDownloadDay = day
            }
            if summary.failures.isEmpty == false {
                self.reportError(summary.failures.joined(separator: "\n"))
            }
            if summary.saved > 0 {
                self.addFolderIfNeeded(folder.path)
                self.appState.refreshImagesFromDisk()
            }
        }
    }

    private func addFolderIfNeeded(_ path: String) {
        guard !settingsManager.settings.folderPaths.contains(path) else { return }
        settingsManager.update { settings in
            settings.folderPaths.append(path)
        }
    }
}
