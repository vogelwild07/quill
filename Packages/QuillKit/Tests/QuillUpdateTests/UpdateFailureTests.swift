#if canImport(Sparkle)
import Foundation
@testable import QuillUpdate
import Sparkle
import Testing

/// Fehler von Sparkle werden zu eigenen Meldungen (ADR-037).
@Suite("Updates: Fehler")
struct UpdateFailureTests {
    @Test(arguments: [
        (1005, UpdateModel.Failure.notInApplications), (1003, .notInApplications),
        (3001, .badSignature), (3002, .badSignature), (3000, .damaged),
        (2001, .network), (1002, .network), (3, .notAllowed),
    ])
    func sparkleCodes(code: Int, expected: UpdateModel.Failure) {
        let error = NSError(domain: SUSparkleErrorDomain, code: code)
        #expect(UpdateUserDriver.failure(for: error) == expected)
    }

    @Test func nestedAndOwnErrors() {
        let own = UpdateController.notAllowed("Archiv")
        let wrapped = NSError(domain: SUSparkleErrorDomain, code: 4005, userInfo: [NSUnderlyingErrorKey: own])
        #expect(UpdateUserDriver.failure(for: wrapped) == .notAllowed)
        let offline = NSError(domain: SUSparkleErrorDomain, code: 9999, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)])
        #expect(UpdateUserDriver.failure(for: offline) == .network)
        #expect(UpdateUserDriver.failure(for: NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Text"])) == .other("Text"))
    }
}
#endif
