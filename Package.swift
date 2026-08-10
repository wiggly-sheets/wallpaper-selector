// swift-tools-version:5.9
import PackageDescription

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
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "WallpaperSelectorTests",
            dependencies: ["WallpaperSelector"],
            path: "SwiftWallpaperSelector/Tests"
        )
    ]
)
