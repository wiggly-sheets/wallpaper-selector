import XCTest
@testable import WallpaperSelector

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storedValue)
    }

    var value: Value {
        withValue { $0 }
    }
}

final class AllSpacesServiceTests: XCTestCase {
    @MainActor
    func testMissingAccessibilityPermissionReturnsManualFallback() {
        var didRequestPermission = false
        var result: AllSpacesApplicationResult?
        let didAutomate = LockedBox(false)
        let service = AllSpacesService(
            openWallpaperSettings: { _ in true },
            systemSettingsProcessIdentifier: { 42 },
            isAccessibilityTrusted: { false },
            requestAccessibilityPermission: { didRequestPermission = true },
            automation: { _, _ in
                didAutomate.withValue { $0 = true }
                return .applied
            }
        )

        service.setEnabled(true) { result = $0 }

        XCTAssertTrue(didRequestPermission)
        XCTAssertFalse(didAutomate.value)
        XCTAssertEqual(
            result,
            .manualActionRequired(enabled: true, reason: .accessibilityPermissionRequired)
        )
    }

    @MainActor
    func testRapidRequestsAreAutomatedAndCompletedInOrder() async {
        let completed = expectation(description: "all requests completed")
        completed.expectedFulfillmentCount = 3
        let automatedValues = LockedBox<[Bool]>([])
        var results: [AllSpacesApplicationResult] = []
        var openCount = 0
        let service = AllSpacesService(
            openWallpaperSettings: { _ in
                openCount += 1
                return true
            },
            systemSettingsProcessIdentifier: { 42 },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            automation: { _, enabled in
                automatedValues.withValue { $0.append(enabled) }
                return .applied
            }
        )

        for enabled in [true, false, true] {
            service.setEnabled(enabled) { result in
                results.append(result)
                completed.fulfill()
            }
        }

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(automatedValues.value, [true, false, true])
        XCTAssertEqual(results, [
            .applied(enabled: true),
            .applied(enabled: false),
            .applied(enabled: true)
        ])
        XCTAssertEqual(openCount, 3)
    }

    @MainActor
    func testRepeatedValueIsNotSuppressedByStaleRequestCache() async {
        let completed = expectation(description: "both requests completed")
        completed.expectedFulfillmentCount = 2
        let automationCount = LockedBox(0)
        let service = AllSpacesService(
            openWallpaperSettings: { _ in true },
            systemSettingsProcessIdentifier: { 42 },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            automation: { _, _ in
                let count = automationCount.withValue { count in
                    count += 1
                    return count
                }
                return count == 1 ? .applied : .alreadySet
            }
        )

        service.setEnabled(true) { _ in completed.fulfill() }
        service.setEnabled(true) { _ in completed.fulfill() }

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(automationCount.value, 2)
    }
}
