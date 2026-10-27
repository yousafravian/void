// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Void",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VoidCore", targets: ["VoidCore"]),
        .executable(name: "Void", targets: ["VoidApp"]),
        .executable(name: "void-mcp", targets: ["VoidMCPCLI"])
    ],
    targets: [
        .target(
            name: "VoidCore",
            path: "Sources/VoidCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("LinkPresentation"),
                .linkedFramework("WebKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("AVKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AppIntents"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "VoidApp",
            dependencies: ["VoidCore"],
            path: "Sources/VoidApp"
        ),
        .executableTarget(
            name: "VoidMCPCLI",
            dependencies: ["VoidCore"],
            path: "Sources/VoidMCPCLI"
        ),
        .testTarget(
            name: "VoidTests",
            dependencies: ["VoidCore"],
            path: "Tests/VoidTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
