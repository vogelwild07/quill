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
        .target(name: "QuillEditor", dependencies: ["QuillModel", "QuillDesign"]),
        .target(name: "QuillExport", dependencies: ["QuillModel"]),
        .target(
            name: "QuillFeatures",
            dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillDesign"]
        ),
        .testTarget(name: "QuillModelTests", dependencies: ["QuillModel"]),
        .testTarget(name: "QuillEditorTests", dependencies: ["QuillEditor"]),
        .testTarget(name: "QuillExportTests", dependencies: ["QuillExport"]),
    ],
    swiftLanguageModes: [.v6]
)
