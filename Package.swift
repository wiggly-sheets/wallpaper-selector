// swift-tools-version:5.9
import PackageDescription

// SwiftPM records the deployment target as the SDK version in the
// `LC_BUILD_VERSION` of the executable, so macOS would treat an app built
// with the 27.2 SDK as a legacy app. Name the real SDK version to the linker:
// the system uses it to decide whether the app gets the current design.
// Keep `macOSDeploymentTarget` in step with the `platforms` list below.
let macOSDeploymentTarget = "13.0"
let macOSSDKVersion = "27.2"

let package = Package(
    name: "WallpaperSelector",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "WallpaperSelector",
            targets: ["WallpaperSelector"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "WallpaperSelector",
            dependencies: [],
            path: "SwiftWallpaperSelector/Sources/WallpaperSelector",
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", macOSDeploymentTarget,
                    "-Xlinker", macOSSDKVersion
                ])
            ]
        ),
        .testTarget(
            name: "WallpaperSelectorTests",
            dependencies: ["WallpaperSelector"],
            path: "SwiftWallpaperSelector/Tests"
        )
    ]
)
