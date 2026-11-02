// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BIPro",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PBIXKit", targets: ["PBIXKit"]),
        .executable(name: "pbix-dump", targets: ["pbix-dump"]),
    ],
    targets: [
        .target(
            name: "CXPress9",
            exclude: ["LICENSE", "VENDORED.md"],
            cSettings: [
                .headerSearchPath("internal"),
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "PBIXKit",
            dependencies: ["CXPress9"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "pbix-dump",
            dependencies: ["PBIXKit"]
        ),
        // Phase B: cột và engine DAX. Swift 6 (strict concurrency) cho hai target mới.
        .target(
            name: "ColumnStore",
            dependencies: ["PBIXKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DAXEngine",
            dependencies: ["ColumnStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DAXTestSupport",
            dependencies: ["ColumnStore", "DAXEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "dax-run",
            dependencies: ["DAXEngine", "ColumnStore", "PBIXKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BIPro",
            dependencies: ["PBIXKit", "ColumnStore", "DAXEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PBIXKitTests",
            dependencies: ["PBIXKit"]
        ),
        .testTarget(
            name: "BIProTests",
            dependencies: ["BIPro", "DAXEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ColumnStoreTests",
            dependencies: ["ColumnStore", "DAXTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DAXEngineTests",
            dependencies: ["DAXEngine", "DAXTestSupport"],
            // Fixture DAX/TSV và golden (Golden/) được đọc qua #filePath, không qua Bundle.module.
            exclude: ["LANG/fixtures", "Golden"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
