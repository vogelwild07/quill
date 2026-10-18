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
        .library(name: "QuillEditorSpike", targets: ["QuillEditorSpike"]),
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
            dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillDesign"],
            resources: [.process("Resources")]
        ),
        // Phase-1-Spike (Wegwerf-Code bis zum ADR „Editor-Architektur“).
        .target(name: "QuillEditorSpike", dependencies: ["QuillEditor", "QuillDesign"]),
        .testTarget(name: "QuillEditorSpikeTests", dependencies: ["QuillEditorSpike", "QuillEditor"]),
        .testTarget(name: "QuillModelTests", dependencies: ["QuillModel"]),
        .testTarget(name: "QuillEditorTests", dependencies: ["QuillEditor"]),
        .testTarget(name: "QuillExportTests", dependencies: ["QuillExport"]),
        .testTarget(name: "QuillFeaturesTests", dependencies: ["QuillFeatures", "QuillModel"]),
    ],
    swiftLanguageModes: [.v6]
)
