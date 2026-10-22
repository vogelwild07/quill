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
            targets: ["QuillFeatures", "QuillModel", "QuillEditorCore", "QuillEditor", "QuillExport", "QuillSync", "QuillDesign"]
        ),
    ],
    dependencies: [
        // Nur für QuillSync (ADR-026): Version fest, die Prüfsumme des vorgebauten
        // Rust-Kerns steht im Paket von automerge-swift und wird von SwiftPM geprüft.
        .package(url: "https://github.com/automerge/automerge-swift.git", exact: "0.7.2"),
    ],
    targets: [
        .target(name: "QuillDesign"),
        .target(name: "QuillModel"),
        // Kern des Editors ohne AppKit, UIKit und SwiftUI (ADR-028): Dokument, Blöcke,
        // Inline-Text, Speichern, Theme-Rechnung. `EditorCoreImportTests` hält das ein.
        .target(name: "QuillEditorCore", dependencies: ["QuillModel"]),
        .target(
            name: "QuillEditor",
            dependencies: ["QuillModel", "QuillEditorCore", "QuillDesign"],
            resources: [.process("Resources")]
        ),
        .target(name: "QuillExport", dependencies: ["QuillModel", "QuillEditorCore"]),
        // Sync über einen Ordner (ADR-026, ADR-029). Einziges Modul mit Automerge;
        // `AutomergeIsolationTests` hält das ein, damit ein Ausstieg auf dieses Modul beschränkt bleibt.
        .target(
            name: "QuillSync",
            dependencies: ["QuillModel", .product(name: "Automerge", package: "automerge-swift")]
        ),
        .target(
            name: "QuillFeatures",
            dependencies: ["QuillModel", "QuillEditorCore", "QuillEditor", "QuillExport", "QuillSync", "QuillDesign"],
            resources: [.process("Resources")]
        ),
        // Beispieldokumente für Editor- und Export-Tests; nicht Teil des Produkts.
        .target(name: "QuillTestFixtures", dependencies: ["QuillEditorCore", "QuillEditor", "QuillModel"], path: "Tests/QuillTestFixtures"),
        .testTarget(name: "QuillModelTests", dependencies: ["QuillModel"]),
        .testTarget(name: "QuillEditorTests", dependencies: ["QuillEditorCore", "QuillEditor", "QuillModel", "QuillTestFixtures"]),
        .testTarget(
            name: "QuillExportTests",
            dependencies: ["QuillExport", "QuillEditorCore", "QuillEditor", "QuillModel", "QuillTestFixtures"],
            exclude: ["Golden"]
        ),
        .testTarget(name: "QuillSyncTests", dependencies: ["QuillSync", "QuillModel", "QuillTestFixtures"]),
        .testTarget(
            name: "QuillFeaturesTests",
            dependencies: ["QuillFeatures", "QuillModel", "QuillEditorCore", "QuillEditor", "QuillSync", "QuillTestFixtures"]
        ),
        // Messungen gegen Schwellen, nur optimiert sinnvoll (docs/performance.md):
        // swift test -c release -Xswiftc -enable-testing --filter QuillPerformanceTests
        .testTarget(
            name: "QuillPerformanceTests",
            dependencies: ["QuillModel", "QuillEditorCore", "QuillEditor", "QuillExport", "QuillFeatures", "QuillSync", "QuillTestFixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
