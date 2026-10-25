import AppKit
import Sparkle

/// Eigene Oberfläche für Sparkle wie später in Quill: Bei „Update gefunden“ antwortet sie
/// erst nach dem (hier simulierten) Backup. `SpikeBackupFails` im Info.plist: Backup
/// scheitert, Antwort „abbrechen“, dann beendet sich die App. Es darf nichts installiert werden.
@MainActor
final class SpikeUserDriver: NSObject, SPUUserDriver {
    private var backupFails: Bool { Bundle.main.object(forInfoDictionaryKey: "SpikeBackupFails") as? Bool == true }

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SpikeDelegate.log("Treiber: Frage nach Erlaubnis (unerwartet)")
        return SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        SpikeDelegate.log("Treiber: gefunden \(appcastItem.versionString), Backup …")
        try? await Task.sleep(for: .milliseconds(300))
        if backupFails {
            SpikeDelegate.log("Treiber: Backup gescheitert, abbrechen und beenden")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                SpikeDelegate.log("beende ohne Freigabe")
                NSApp.terminate(nil)
            }
            return .dismiss
        }
        SpikeDelegate.log("Treiber: Backup fertig, installieren")
        return .install
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        SpikeDelegate.log("Treiber: kein Update")
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        SpikeDelegate.log("Treiber: Fehler \((error as NSError).code)")
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) { SpikeDelegate.log("Treiber: lade") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        SpikeDelegate.log("Treiber: bereit, installieren")
        return .install
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        SpikeDelegate.log("Treiber: installiere (beendet: \(applicationTerminated))")
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() { SpikeDelegate.log("Treiber: schließen") }
}
