// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NotepadPlusPlusMac",
    platforms: [
        .macOS(.v14)  // Requires macOS 14 Sonoma for latest SwiftUI APIs
    ],
    products: [
        .executable(
            name: "NotepadPlusPlusMac",
            targets: ["NotepadPlusPlusMac"]
        ),
    ],
    dependencies: [
        // Swift Argument Parser for CLI tools
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Swift Collections for ordered sets/dictionaries
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        // Highlightr for syntax highlighting (pure Swift)
        .package(url: "https://github.com/raspu/Highlightr", from: "2.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotepadPlusPlusMac",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            exclude: ["Resources"],  // Info.plist is for a future .app bundle
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=100"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "NotepadPlusPlusMacTests",
            dependencies: ["NotepadPlusPlusMac"],
            path: "Tests/NotepadPlusPlusMacTests"
        ),
    ]
)