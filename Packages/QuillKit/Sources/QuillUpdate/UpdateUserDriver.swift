#if canImport(Sparkle)
import Foundation
import Sparkle

/// Eigene Oberfläche für Sparkle (ADR-037): gibt alles an `UpdateModel` weiter. Bei
/// „Update gefunden“ antwortet sie erst nach dem Backup mit „installieren“.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private let model: UpdateModel
    private let backup: @MainActor (String) async throws -> Void
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    init(model: UpdateModel, backup: @escaping @MainActor (String) async throws -> Void) {
        self.model = model
        self.backup = backup
    }

    /// Quill fragt beim ersten Start selbst; Sparkle fragt nie (`SUEnableAutomaticChecks`).
    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        model.beginUserInitiatedCheck(cancel: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        let version = appcastItem.displayVersionString
        let offer = UpdateModel.Offer(version: version, notes: appcastItem.itemDescription)
        let backup = backup
        switch await model.offer(offer, backup: { try await backup(version) }) {
        case .install: return .install
        case .dismiss: return .dismiss
        case .skip: return .skip
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model.noUpdate(acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        UpdateController.logger.error("Update gescheitert: \(error as NSError, privacy: .public)")
        model.failed(Self.failure(for: error), acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        model.downloadStarted(cancel: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        guard expectedLength > 0 else { return }
        model.downloadProgress(Double(receivedLength) / Double(expectedLength))
    }

    func showDownloadDidStartExtractingUpdate() {
        model.preparing()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    /// Das Backup ist schon angelegt (bei „Update gefunden“).
    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        .install
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        model.installing(applicationTerminated: applicationTerminated, retry: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        model.bringToFront()
    }

    func dismissUpdateInstallation() {
        model.dismissedBySparkle()
    }

    /// Fehler von Sparkle (Codes aus `SUErrors.h`) oder von Quill selbst, auch verschachtelt.
    nonisolated static func failure(for error: any Error) -> UpdateModel.Failure {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == UpdateController.notAllowedDomain { return .notAllowed }
            if error.domain == NSURLErrorDomain { return .network }
            if error.domain == SUSparkleErrorDomain {
                switch Int(error.code) {
                case 1003, 1005: return .notInApplications
                case 3001, 3002: return .badSignature
                case 3000: return .damaged
                case 1000, 1002, 2001: return .network
                case 3: return .notAllowed
                default: break
                }
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .other((error as NSError).localizedDescription)
    }
}
#endif
