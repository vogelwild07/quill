import Foundation
@testable import QuillUpdate
import Testing

/// Woher und wie oft (ADR-037).
@Suite("Updates: Regeln")
struct UpdatePolicyTests {
    @Test func feedIsTheLatestReleaseOnGitHub() {
        #expect(UpdatePolicy.feedURL.absoluteString == "https://github.com/vogelwild07/quill/releases/latest/download/appcast.xml")
        #expect(UpdatePolicy.isAllowed(UpdatePolicy.feedURL))
    }

    @Test(arguments: [
        "https://github.com/vogelwild07/quill/releases/download/v0.5.0/Quill-0.5.0.dmg",
        "https://GitHub.com/vogelwild07/quill/releases/latest/download/appcast.xml",
    ])
    func allowed(_ string: String) throws {
        #expect(UpdatePolicy.isAllowed(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "http://github.com/vogelwild07/quill/releases/download/v0.5.0/Quill-0.5.0.dmg",
        "https://github.com.example.org/vogelwild07/quill/releases/download/v0.5.0/Quill.dmg",
        "https://evilgithub.com/vogelwild07/quill/releases/download/v0.5.0/Quill.dmg",
        "https://gist.github.com/vogelwild07/quill/releases/download/v0.5.0/Quill.dmg",
        "https://example.org/vogelwild07/quill/releases/download/v0.5.0/Quill.dmg",
        "https://github.com/someone/quill/releases/download/v0.5.0/Quill.dmg",
        "https://github.com/vogelwild07/quill-archive/releases/download/v0.5.0/Quill.dmg",
        "https://github.com/vogelwild07/quill/archive/refs/heads/main.zip",
        "https://github.com/vogelwild07/quill/releases",
        "https://github.com/vogelwild07/quill/releases/../../../evil/x.dmg",
        "https://user:secret@github.com/vogelwild07/quill/releases/download/v1/Quill.dmg",
        "https://github.com:8443/vogelwild07/quill/releases/download/v1/Quill.dmg",
        "http://127.0.0.1:8765/appcast.xml",
        "file:///Users/x/appcast.xml",
    ])
    func refused(_ string: String) throws {
        #expect(!UpdatePolicy.isAllowed(try #require(URL(string: string))), "\(string)")
    }

    @Test func testServerOnlyWhenAllowed() throws {
        let url = try #require(URL(string: "http://127.0.0.1:8765/appcast.xml"))
        #expect(UpdatePolicy.isAllowed(url, allowsTestServer: true))
        #expect(!UpdatePolicy.isAllowed(url))
        #expect(!UpdatePolicy.isAllowed(try #require(URL(string: "http://localhost:8765/appcast.xml")), allowsTestServer: true))
    }

    @Test func switchedOffNeverChecks() {
        let now = Date.now
        for last in [nil, now.addingTimeInterval(-10 * 24 * 3600), now.addingTimeInterval(3600)] as [Date?] {
            #expect(!UpdatePolicy.mayCheckAutomatically(enabled: false, lastAttempt: last, now: now))
        }
    }

    @Test func atMostOnceADay() {
        let now = Date.now
        #expect(UpdatePolicy.mayCheckAutomatically(enabled: true, lastAttempt: nil, now: now))
        #expect(!UpdatePolicy.mayCheckAutomatically(enabled: true, lastAttempt: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(UpdatePolicy.mayCheckAutomatically(enabled: true, lastAttempt: now.addingTimeInterval(-24 * 3600), now: now))
        // Uhr zurückgestellt: Der Versuch „in der Zukunft“ hält die Suche nicht auf Dauer auf.
        #expect(UpdatePolicy.mayCheckAutomatically(enabled: true, lastAttempt: now.addingTimeInterval(3600), now: now))
    }
}
