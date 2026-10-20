// swift-tools-version: 6.2
import PackageDescription

// Spike zu ADR-026 (Phase 10.1): Misst Automerge gegen die Kriterien des ADR.
// Nicht Teil der App: App und QuillKit binden dieses Paket nie ein
// (`SpikeIsolationTests` in QuillKit). Ablauf und Messwerte: README.md.
let package = Package(
    name: "AutomergeSpike",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    dependencies: [
        // Version fest; die Prüfsumme des vorgebauten Rust-Kerns steht im Paket
        // von automerge-swift und wird von SwiftPM beim Laden geprüft.
        .package(url: "https://github.com/automerge/automerge-swift.git", exact: "0.7.2"),
        .package(path: "../../Packages/QuillKit"),
    ],
    targets: [
        .target(
            name: "AutomergeSpike",
            dependencies: [
                .product(name: "Automerge", package: "automerge-swift"),
                .product(name: "QuillKit", package: "QuillKit"),
            ]
        ),
        .executableTarget(name: "automerge-spike-measure", dependencies: ["AutomergeSpike"]),
        .testTarget(name: "AutomergeSpikeTests", dependencies: ["AutomergeSpike"]),
    ],
    swiftLanguageModes: [.v6]
)
