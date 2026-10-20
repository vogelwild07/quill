import Foundation
import QuillSync
import Synchronization

/// Echter Dateizugriff, der vor jedem Anlegen `onCreate` aufruft (z. B. um mitten im
/// Abgleich zu pausieren).
final class HookedFileAccess: SyncFileAccess {
    private let real = CoordinatedFileAccess()
    let onCreate = Mutex<(@Sendable (URL) -> Void)?>(nil)

    func contents(of directory: URL) throws -> [SyncFileEntry] { try real.contents(of: directory) }
    func read(_ url: URL) throws -> Data { try real.read(url) }
    func create(_ url: URL, with data: Data) throws {
        onCreate.withLock { $0 }?(url)
        try real.create(url, with: data)
    }
    func replace(_ url: URL, with data: Data) throws { try real.replace(url, with: data) }
    func requestDownload(_ url: URL) throws { try real.requestDownload(url) }
}
