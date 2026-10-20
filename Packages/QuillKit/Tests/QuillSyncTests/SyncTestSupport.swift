import CryptoKit
import Foundation
import ImageIO
import QuillModel
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import QuillSync

/// Ein Gerät im Test: eigener Store nur im Arbeitsspeicher, gemeinsamer Wegwerf-Ordner.
/// Nie der echte Store (ADR-029).
struct TestDevice {
    let name: String
    let store: PageStore
    let engine: SyncEngine
    let gate: SyncGate
    let files: TestFileAccess
    let deviceID: UUID

    init(_ name: String, folder: URL) async throws {
        self.name = name
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        gate = SyncGate()
        files = TestFileAccess()
        engine = SyncEngine(store: store, folder: folder, gate: gate, deviceName: name, files: files)
        deviceID = UUID()
        try await store.setSyncDeviceID(deviceID)
    }

    /// Gleicht ab; beim ersten Mal mit einem Ordner, den es schon gibt, mit Zustimmung.
    @discardableResult
    func sync(progress: @escaping @Sendable (SyncProgress) -> Void = { _ in }) async throws -> SyncReport {
        do {
            let report = try await engine.sync(connectedFolderID: files.connected, progress: progress)
            files.connected = report.folderID
            return report
        } catch SyncFailure.unknownFolder(let id) where files.connected == nil {
            files.connected = id
            return try await engine.sync(connectedFolderID: id, progress: progress)
        }
    }

    func page(titled title: String) async throws -> PageSnapshot {
        try #require(try await store.pageSnapshots().first { $0.title == title }, "Seite \(title) fehlt auf \(name)")
    }

    func blocks(of title: String) async throws -> [BlockSnapshot] {
        try await store.blocks(of: page(titled: title).id)
    }

    func texts(of title: String) async throws -> [String] {
        try await blocks(of: title).map(\.text)
    }

    /// Neue Seite mit Absätzen.
    @discardableResult
    func createPage(_ title: String, texts: [String] = []) async throws -> (page: UUID, blocks: [UUID]) {
        let page = try await store.createPage(title: title)
        let blocks = texts.map { BlockSnapshot(id: UUID(), text: $0) }
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return (page, blocks.map(\.id))
    }

    func edit(_ pageID: UUID, _ blockID: UUID, _ change: (inout BlockSnapshot) -> Void) async throws {
        var block = try #require(try await store.blocks(of: pageID).first { $0.id == blockID })
        change(&block)
        try await store.applyEdits(pageID, BlockEdits(upserts: [block]))
    }
}

/// Wegwerf-Ordner für einen Test.
struct TestFolder: ~Copyable {
    let url = FileManager.default.temporaryDirectory.appending(path: "QuillSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var layout: SyncFolderLayout { SyncFolderLayout(chosenFolder: url) }

    /// Prüfsumme je Datei mit Pfad relativ zum Ordner.
    func fingerprint() throws -> [String: String] {
        var result: [String: String] = [:]
        // Ohne Symlinks: `/var` im Temp-Pfad ist `/private/var`.
        let base = url.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        for case let file as URL in enumerator where (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            let path = file.resolvingSymlinksInPath().path(percentEncoded: false)
            result[String(path.dropFirst(base.count)).trimmingPrefix("/").description] = SHA256.hash(data: try Data(contentsOf: file)).description
        }
        return result
    }

    /// Alle Dateien mit Pfad relativ zum Ordner `Quill`.
    func files() throws -> Set<String> {
        let prefix = SyncFolderLayout.folderName + "/"
        return Set(try fingerprint().keys.compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil })
    }
}

/// Echter Dateizugriff mit Eingriffen für Tests: Dateien als „noch nicht geladen“
/// melden, beim Schreiben pausieren oder einen Fehler werfen.
final class TestFileAccess: SyncFileAccess {
    struct State {
        var connected: UUID?
        var notDownloaded: Set<String> = []
        var downloadRequests: [String] = []
        var created: [String] = []
        var onCreate: (@Sendable (URL) throws -> Void)?
        var onContents: (@Sendable (URL) throws -> Void)?
    }

    private let real = CoordinatedFileAccess()
    let state = Mutex(State())

    var connected: UUID? {
        get { state.withLock { $0.connected } }
        set { state.withLock { $0.connected = newValue } }
    }

    func contents(of directory: URL) throws -> [SyncFileEntry] {
        try state.withLock { $0.onContents }?(directory)
        let hidden = state.withLock { $0.notDownloaded }
        return try real.contents(of: directory).map { entry in
            var entry = entry
            if hidden.contains(directory.appending(path: entry.name).lastPathComponent) || hidden.contains(entry.name) {
                entry.isDownloaded = false
            }
            return entry
        }
    }

    func read(_ url: URL) throws -> Data {
        if state.withLock({ $0.notDownloaded.contains(url.lastPathComponent) }) {
            Issue.record("Nicht geladene Datei gelesen: \(url.lastPathComponent)")
        }
        return try real.read(url)
    }

    func create(_ url: URL, with data: Data) throws {
        try state.withLock { $0.onCreate }?(url)
        try real.create(url, with: data)
        state.withLock { $0.created.append(url.lastPathComponent) }
    }

    func replace(_ url: URL, with data: Data) throws {
        try state.withLock { $0.onCreate }?(url)
        try real.replace(url, with: data)
    }

    func requestDownload(_ url: URL) throws {
        state.withLock { $0.downloadRequests.append(url.lastPathComponent) }
    }
}

enum TestImage {
    /// Kleines PNG in einer Farbe, mit der App erzeugt, nicht vom Test-Runner geladen.
    static func png(red: CGFloat, width: Int = 4, height: Int = 3) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: red, green: 0.2, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
