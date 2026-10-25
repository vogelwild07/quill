import Foundation
import Testing
@testable import QuillModel

/// Anlass im Namen eines Backup-Ordners (`<Zeitpunkt>_<Anlass>`). Die Texte stehen in
/// vorhandenen Backups und dürfen sich nicht ändern.
@Suite("Backup-Anlass im Ordnernamen")
struct BackupSlugTests {
    static let reasons: [StoreBackup.Reason] = [
        .launch, .quit, .beforeMigration(from: "1.0.0", to: "2.0.0"),
        .beforeEmptyingTrash, .beforeRestore, .beforeMove, .setAside, .beforeSync, .beforeUpdate(to: "0.5.0"),
    ]

    @Test func namesStayAsBefore() {
        #expect(Self.reasons.map(\.slug) == [
            "start", "beenden", "vor-migration-1.0.0-2.0.0",
            "vor-papierkorb-leeren", "vor-wiederherstellen", "vor-umzug", "beiseitegelegt", "vor-sync",
            "vor-update-0.5.0",
        ])
    }

    /// Die Version kommt aus der Versionsliste und darf keinen Pfad bilden (ADR-037).
    @Test(arguments: [("0.5.0", "0.5.0"), ("1.0.0-beta.2", "1.0.0-beta.2"), ("../../x", "unbekannt"), ("a/b", "unbekannt"), ("", "unbekannt"), ("1..2", "unbekannt"), (String(repeating: "9", count: 21), "unbekannt"), ("0.5 neu", "unbekannt")])
    func updateVersionIsSafeInANames(version: String, expected: String) {
        #expect(StoreBackup.Reason.beforeUpdate(to: version).slug == "vor-update-" + expected)
    }

    @Test(arguments: reasons)
    func everyReasonReadsBackAsItsKind(_ reason: StoreBackup.Reason) {
        #expect(StoreBackup.Kind(slug: Substring(reason.slug)) == reason.kind)
        // Mit Zähler für doppelte Namen.
        #expect(StoreBackup.Kind(slug: Substring(reason.slug + "-2")) == reason.kind)
    }

    /// Jede bekannte Art hat einen Anlass, der zu ihr zurückführt.
    @Test func everyKindHasAReason() {
        let known = StoreBackup.Kind.allCases.filter { $0 != .other }
        #expect(Set(Self.reasons.map(\.kind).map { "\($0)" }) == Set(known.map { "\($0)" }))
    }

    @Test func unknownNamesAreOther() {
        #expect(StoreBackup.Kind(slug: "irgendwas") == .other)
        #expect(StoreBackup.Kind(slug: "") == .other)
    }
}
