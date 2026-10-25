import AppKit
import Sparkle

/// Spike für ADR-037: Aktualisiert sich eine ad hoc signierte Sandbox-App mit Sparkle 2?
/// Schreibt jeden Schritt in `spike.log` im eigenen Container; `run-spike.sh` liest mit.
@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private let driver = SpikeUserDriver()
    private var ownUpdater: SPUUpdater?

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    static let logURL = URL(filePath: NSHomeDirectory()).appending(path: "spike.log")

    static func log(_ text: String) {
        let line = "\(Date().ISO8601Format()) v\(version) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log("gestartet aus \(Bundle.main.bundlePath)")
        if Bundle.main.object(forInfoDictionaryKey: "SpikeOwnDriver") as? Bool == true {
            let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
            ownUpdater = updater
            do { try updater.start() } catch { Self.log("Start des Updaters gescheitert: \(error)"); return }
            updater.checkForUpdates()
            Self.log("suche (eigene Oberfläche)")
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try controller.updater.start()
        } catch {
            Self.log("Start des Updaters gescheitert: \(error)")
            return
        }
        controller.updater.automaticallyDownloadsUpdates = true
        controller.updater.checkForUpdatesInBackground()
        Self.log("suche")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { Self.log("gefunden \(item.versionString)") }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { Self.log("kein Update") }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        MainActor.assumeIsolated { Self.log("abgebrochen: \(error as NSError)") }
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { Self.log("geladen \(item.versionString)") }
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        MainActor.assumeIsolated { Self.log("Laden gescheitert: \(error as NSError)") }
    }

    /// Wie das Backup vor der Installation in Quill: Mit `SpikePostpone` im Info.plist gibt
    /// die App die Installation nie frei und beendet sich nach drei Sekunden. Prüft, ob
    /// Sparkle dann trotzdem installiert.
    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard Bundle.main.object(forInfoDictionaryKey: "SpikePostpone") as? Bool == true else {
                Self.log("Freigabe sofort")
                return false
            }
            Self.log("Freigabe verweigert, beende in 3 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Self.log("beende ohne Freigabe")
                NSApp.terminate(nil)
            }
            return true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated { Self.log("installiere \(item.versionString) sofort") }
        immediateInstallationBlock()
        return true
    }
}

let app = NSApplication.shared
let delegate = SpikeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
