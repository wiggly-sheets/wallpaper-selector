import XCTest
@testable import WallpaperSelector

final class DailyDownloadServiceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    /// The stored day is what makes the download run once a day: the same
    /// day must not run twice, and a new day must run again.
    func testTheDownloadRunsOncePerDay() {
        let noon = date(2026, 11, 23)

        XCTAssertTrue(DailyDownloadSchedule.isDue(
            enabled: true,
            sources: [.wallhaven],
            lastDay: "2026-11-22",
            now: noon
        ))
        XCTAssertFalse(DailyDownloadSchedule.isDue(
            enabled: true,
            sources: [.wallhaven],
            lastDay: "2026-11-23",
            now: noon
        ))
        // A file without a stored day downloads on the first check.
        XCTAssertTrue(DailyDownloadSchedule.isDue(
            enabled: true,
            sources: [.wallhaven],
            lastDay: nil,
            now: date(2026, 11, 24)
        ))
    }

    /// The toggle is off by default, and a download without a source has
    /// nothing to fetch.
    func testTheDownloadNeedsTheToggleAndASource() {
        let noon = date(2026, 11, 23)

        XCTAssertFalse(DailyDownloadSchedule.isDue(
            enabled: false,
            sources: [.wallhaven],
            lastDay: nil,
            now: noon
        ))
        XCTAssertFalse(DailyDownloadSchedule.isDue(
            enabled: true,
            sources: [],
            lastDay: nil,
            now: noon
        ))
    }

    /// The day is written in the local calendar, so the stored value follows
    /// the day the user sees on the clock.
    func testTheDayOfTheDateIsWrittenAsAnIsoDay() {
        XCTAssertEqual(DailyDownloadSchedule.day(for: date(2026, 11, 23), calendar: calendar), "2026-11-23")
        XCTAssertEqual(DailyDownloadSchedule.day(for: date(2026, 1, 2, hour: 0), calendar: calendar), "2026-01-02")
    }
}
