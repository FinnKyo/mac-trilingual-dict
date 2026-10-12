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
                .product(name: "IPADic", package: "Mecab-Swift")
            ],
            path: "Sources/DictTranslator"
        ),
        .testTarget(
            name: "DictTranslatorTests",
            dependencies: ["DictTranslator"],
            path: "Tests/DictTranslatorTests"
        )
    ]
)
