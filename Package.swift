// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DictTranslator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DictTranslator", targets: ["DictTranslator"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DictTranslator",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/DictTranslator"
        ),
        .testTarget(
            name: "DictTranslatorTests",
            dependencies: ["DictTranslator"],
            path: "Tests/DictTranslatorTests"
        )
    ]
)
