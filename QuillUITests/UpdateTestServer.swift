import Foundation
import Network
import Synchronization

/// Kleiner HTTP-Server auf 127.0.0.1 für `UpdateUITests` (ADR-037): liefert eine
/// unsignierte Versionsliste aus und zählt, wie oft Quill sie abfragt. Einzige Stelle
/// außerhalb von QuillUpdate mit Netz (`UpdateIsolationTests`). Nie erreichbar von außen.
final class UpdateTestServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "UpdateTestServer")
    private let state = Mutex(State())

    private struct State {
        var requests = 0
        var port: UInt16?
        var failure: String?
    }

    /// Versionsliste mit einer neueren Version, ohne EdDSA-Signatur: Quill muss sie ablehnen.
    static let appcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><title>Quill</title>
        <item><title>Quill 99.0.0</title><sparkle:version>9999</sparkle:version>
        <sparkle:shortVersionString>99.0.0</sparkle:shortVersionString>
        <enclosure url="http://127.0.0.1/Quill-99.0.0.dmg" type="application/octet-stream" sparkle:edSignature="AAAA" length="1"/>
        </item></channel></rss>
        """

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready: state.withLock { $0.port = self.listener.port?.rawValue }
            case .failed(let error): state.withLock { $0.failure = "\(error)" }
            default: break
            }
        }
        listener.start(queue: queue)
    }

    deinit {
        listener.cancel()
    }

    /// Port, sobald der Server bereit ist (höchstens fünf Sekunden).
    func waitForPort() throws -> UInt16 {
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            let current = state.withLock { $0 }
            if let port = current.port { return port }
            if let failure = current.failure { throw ServerError(message: failure) }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw ServerError(message: "Server nicht bereit")
    }

    var requests: Int { state.withLock { $0.requests } }

    struct ServerError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let found = request.hasPrefix("GET /appcast.xml ")
            if found { state.withLock { $0.requests += 1 } }
            let body = found ? Self.appcast : "nicht gefunden"
            let status = found ? "200 OK" : "404 Not Found"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: application/xml\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
