// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DictTranslator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DictTranslator", targets: ["DictTranslator"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        // MeCab 日语形态素分析 + IPADic 词典（句子注音、词的原形）
        .package(url: "https://github.com/shinjukunian/Mecab-Swift", revision: "1f096492e37fc05fc2e7304091f54889974c5368")
    ],
    targets: [
        .executableTarget(
            name: "DictTranslator",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "Mecab-Swift", package: "Mecab-Swift"),
                .product(name: "IPADic", package: "Mecab-Swift"),
                "llama"
            ],
            path: "Sources/DictTranslator",
            linkerSettings: [
                // 打包后 llama.framework 位于 Contents/Frameworks
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // llama.cpp 官方发布的 xcframework（arm64 + x86_64，含 Metal），用于本地运行混元翻译模型 Hy-MT2 的 GGUF
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11988/llama-b11988-xcframework.zip",
            checksum: "733ae95d8fe9fe45eecdf335a8a634424e280c36aa626c0c2fda7488f049c845"
        ),
        .testTarget(
            name: "DictTranslatorTests",
            dependencies: ["DictTranslator"],
            path: "Tests/DictTranslatorTests"
        )
    ]
)
