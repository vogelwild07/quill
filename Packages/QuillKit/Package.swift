// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuillKit",
    defaultLocalization: "de",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "QuillKit",
            targets: ["QuillFeatures", "QuillModel", "QuillEditor", "QuillExport", "QuillDesign"]
        ),
    ],
    targets: [
        .target(name: "QuillDesign"),
        .target(name: "QuillModel"),
        .target(
            name: "QuillEditor",
            dependencies: ["QuillModel", "QuillDesign"],
            resources: [.process("Resources")]
        ),
        .target(name: "QuillExport", dependencies: ["QuillModel", "QuillEditor"]),
        .target(
            name: "QuillFeatures",
            dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillDesign"],
            resources: [.process("Resources")]
        ),
        // Beispieldokumente für Editor- und Export-Tests; nicht Teil des Produkts.
        .target(name: "QuillTestFixtures", dependencies: ["QuillEditor", "QuillModel"], path: "Tests/QuillTestFixtures"),
        .testTarget(name: "QuillModelTests", dependencies: ["QuillModel"]),
        .testTarget(name: "QuillEditorTests", dependencies: ["QuillEditor", "QuillModel", "QuillTestFixtures"]),
        .testTarget(
            name: "QuillExportTests",
            dependencies: ["QuillExport", "QuillEditor", "QuillModel", "QuillTestFixtures"],
            exclude: ["Golden"]
        ),
        .testTarget(name: "QuillFeaturesTests", dependencies: ["QuillFeatures", "QuillModel", "QuillEditor"]),
        // Messungen gegen Schwellen, nur optimiert sinnvoll (docs/performance.md):
        // swift test -c release -Xswiftc -enable-testing --filter QuillPerformanceTests
        .testTarget(
            name: "QuillPerformanceTests",
            dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillFeatures", "QuillTestFixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
