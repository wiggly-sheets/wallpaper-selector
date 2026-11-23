import XCTest
@testable import WallpaperSelector

final class SpaceInventoryTests: XCTestCase {
    func testSpacesKeepTheOrderOfTheirDisplay() {
        let configuration: [String: Any] = [
            "Management Data": [
                "Monitors": [[
                    "Display Identifier": "Main",
                    "Current Space": ["uuid": "aaaaaaaa-0000-0000-0000-000000000001"],
                    "Spaces": [
                        ["uuid": "aaaaaaaa-0000-0000-0000-000000000001", "type": 0],
                        // A full-screen app is not a desktop Space.
                        ["uuid": "ffffffff-0000-0000-0000-000000000009", "type": 4],
                        ["uuid": "bbbbbbbb-0000-0000-0000-000000000002", "type": 0],
                    ],
                ], [
                    "Display Identifier": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                    "Spaces": [
                        ["uuid": "cccccccc-0000-0000-0000-000000000003", "type": 0],
                    ],
                ]],
            ],
        ]

        let spaces = SpaceInventory.spaces(from: configuration)

        XCTAssertEqual(spaces.map(\.id), [
            "AAAAAAAA-0000-0000-0000-000000000001",
            "BBBBBBBB-0000-0000-0000-000000000002",
            "CCCCCCCC-0000-0000-0000-000000000003",
        ])
        XCTAssertEqual(spaces.map(\.index), [1, 2, 1])
        XCTAssertEqual(spaces.map(\.isCurrent), [true, false, false])
        XCTAssertEqual(spaces[0].displayName, "Main Display")
        XCTAssertEqual(spaces[2].displayName, "Display 37D8")
    }

    func testAnEmptyPreferenceHasNoSpaces() {
        XCTAssertTrue(SpaceInventory.spaces(from: [:]).isEmpty)
        XCTAssertTrue(
            SpaceInventory.spaces(from: ["Management Data": ["Monitors": []]]).isEmpty
        )
    }
}
