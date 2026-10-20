import Foundation
import Testing
@testable import QuillSync

@Suite("Sync-Ordner: Pfade, quill.json, Geräte")
struct SyncFolderLayoutTests {
    let layout = SyncFolderLayout(chosenFolder: URL(filePath: "/tmp/Ordner", directoryHint: .isDirectory))
    let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!
    let page = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!

    @Test func pathsFollowTheFormat() {
        #expect(layout.manifest.path == "/tmp/Ordner/Quill/quill.json")
        #expect(layout.device(device).path == "/tmp/Ordner/Quill/devices/\(device.uuidString).json")
        #expect(layout.tree(device: device).path == "/tmp/Ordner/Quill/tree/\(device.uuidString)")
        let pageFolder = layout.page(page, device: device)
        #expect(pageFolder.path == "/tmp/Ordner/Quill/pages/\(page.uuidString)/\(device.uuidString)")
        #expect(SyncFolderLayout.changes(42, in: pageFolder).lastPathComponent == "000000000042.changes")
        #expect(SyncFolderLayout.snapshot(in: pageFolder).lastPathComponent == "snapshot")
    }

    @Test func changeNumbersParseOnlyOwnNames() {
        #expect(SyncFolderLayout.changesNumber("000000000042.changes") == 42)
        #expect(SyncFolderLayout.changesNumber(SyncFolderLayout.changesFileName(7)) == 7)
        for name in ["42.changes", "000000000042.txt", "snapshot", ".000000000042.changes.icloud", "00000000004a.changes", "-00000000042.changes"] {
            #expect(SyncFolderLayout.changesNumber(name) == nil, "\(name)")
        }
    }

    @Test func assetsAreNamedByContent() {
        let data = Data("Bild".utf8)
        let first = layout.asset(data, fileExtension: "PNG")
        #expect(first == layout.asset(data, fileExtension: "png"))
        #expect(first.lastPathComponent == "\(SyncFolderLayout.sha256(data)).png")
        #expect(first.lastPathComponent.count == 64 + 4)
        #expect(first != layout.asset(Data("anderes Bild".utf8), fileExtension: "png"))
    }

    @Test func manifestRoundTrip() throws {
        let manifest = FolderManifest(createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try FolderManifest.decode(manifest.encoded()) == manifest)
        let device = DeviceInfo(id: device, name: "Mac", lastSeen: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try DeviceInfo.decode(device.encoded()) == device)
    }

    @Test func newerOrBrokenManifestIsRejected() throws {
        let newer = Data(#"{"format": 2, "folderID": "00000000-0000-4000-8000-000000000001", "encrypted": false, "createdAt": "2027-01-15T08:00:00Z", "cipher": "x"}"#.utf8)
        #expect(throws: SyncError.newerFormat(2)) { try FolderManifest.decode(newer) }
        let newerShape = Data(#"{"format": 3}"#.utf8)
        #expect(throws: SyncError.newerFormat(3)) { try FolderManifest.decode(newerShape) }
        #expect(throws: SyncError.self) { try FolderManifest.decode(Data("kaputt".utf8)) }
        #expect(throws: SyncError.self) { try DeviceInfo.decode(Data("{}".utf8)) }
    }
}
