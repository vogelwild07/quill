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
        .target(name: "QuillExport", dependencies: ["QuillModel"]),
        .target(
            name: "QuillFeatures",
            dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillDesign"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "QuillModelTests", dependencies: ["QuillModel"]),
        .testTarget(name: "QuillEditorTests", dependencies: ["QuillEditor", "QuillModel"]),
        .testTarget(name: "QuillExportTests", dependencies: ["QuillExport"]),
        .testTarget(name: "QuillFeaturesTests", dependencies: ["QuillFeatures", "QuillModel", "QuillEditor"]),
    ],
    swiftLanguageModes: [.v6]
)
