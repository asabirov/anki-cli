// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "anki-notes-cli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AnkiNotesCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AnkiNotesCore"
        ),
        .executableTarget(
            name: "anki-notes-cli",
            dependencies: ["AnkiNotesCore"],
            path: "Sources/anki-notes-cli"
        ),
        // Requires Xcode (not just Command Line Tools) for XCTest
        // .testTarget(
        //     name: "AnkiNotesCoreTests",
        //     dependencies: ["AnkiNotesCore"],
        //     path: "Tests/AnkiNotesCoreTests"
        // ),
    ]
)
