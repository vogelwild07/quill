import Foundation
import QuillEditorCore
@testable import QuillFeatures
import QuillModel
import Testing

/// Erinnerungen an To-dos (15.4, ADR-033), mit einem Ersatz statt der Mitteilungen des Macs.
@Suite("Erinnerungen")
@MainActor
struct RemindersTests {
    let store: PageStore
    let center: MemoryReminderCenter
    let reminders: Reminders
    let later = Date.now.addingTimeInterval(3600)

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        center = MemoryReminderCenter()
        reminders = Reminders(store: store, center: center, delay: .milliseconds(10))
    }

    func page(_ title: String, _ blocks: [BlockSnapshot]) async throws -> UUID {
        let id = try await store.createPage(title: title)
        try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return id
    }

    static func todo(_ text: String, checked: Bool = false) -> BlockSnapshot {
        BlockSnapshot(id: UUID(), kindRaw: BlockKind.todo.rawValue, text: text, properties: BlockProperties(isChecked: checked))
    }

    /// Wartet, bis der Abgleich nach einer Speicherung durch ist.
    func waitFor(_ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition(), sourceLocation: sourceLocation)
    }

    @Test func schedulesWithTextAndPageTitle() async throws {
        let todo = Self.todo("Reifen wechseln")
        let pageID = try await page("Auto", [todo])
        #expect(try await reminders.set(blockID: todo.id, pageID: pageID, date: later))

        let expected = Reminder(blockID: todo.id, pageID: pageID, date: later, text: "Reifen wechseln", pageTitle: "Auto")
        #expect(await center.reminders == [todo.id: expected])
        #expect(reminders.byBlock == [todo.id: expected])
        #expect(reminders.blocks(onPage: pageID) == [todo.id])
        #expect(await center.authorizations == 1)
    }

    @Test func onlyOpenTodosInTheFuture() async throws {
        let paragraph = BlockSnapshot(id: UUID(), text: "Absatz")
        let done = Self.todo("Erledigt", checked: true)
        let open = Self.todo("Offen")
        let pageID = try await page("Liste", [paragraph, done, open])

        await #expect(throws: Reminders.Failure.notATodo) { try await reminders.set(blockID: paragraph.id, pageID: pageID, date: later) }
        await #expect(throws: Reminders.Failure.notATodo) { try await reminders.set(blockID: done.id, pageID: pageID, date: later) }
        await #expect(throws: Reminders.Failure.past) {
            try await reminders.set(blockID: open.id, pageID: pageID, date: .now.addingTimeInterval(-60))
        }
        try await store.trash(pageID)
        await #expect(throws: Reminders.Failure.notATodo) { try await reminders.set(blockID: open.id, pageID: pageID, date: later) }
        #expect(await center.reminders.isEmpty)
    }

    @Test func deniedNotificationsScheduleNothing() async throws {
        let denied = MemoryReminderCenter(allowed: false)
        let reminders = Reminders(store: store, center: denied)
        let todo = Self.todo("Anrufen")
        let pageID = try await page("Heute", [todo])
        #expect(try await reminders.set(blockID: todo.id, pageID: pageID, date: later) == false)
        #expect(await denied.reminders.isEmpty)
        #expect(reminders.byBlock.isEmpty)
    }

    @Test func removing() async throws {
        let todo = Self.todo("Anrufen")
        let pageID = try await page("Heute", [todo])
        _ = try await reminders.set(blockID: todo.id, pageID: pageID, date: later)
        await reminders.remove(blockID: todo.id)
        #expect(await center.reminders.isEmpty)
        #expect(reminders.byBlock.isEmpty)
    }

    @Test func startReadsWhatIsPlanned() async throws {
        let todo = Self.todo("Anrufen")
        let pageID = try await page("Heute", [todo])
        let planned = Reminder(blockID: todo.id, pageID: pageID, date: later, text: "Anrufen", pageTitle: "Heute")
        await center.schedule(planned)
        await center.schedule(Reminder(blockID: UUID(), pageID: pageID, date: later, text: "Gelöscht", pageTitle: "Heute"))

        reminders.start()
        await reminders.settle()
        #expect(reminders.byBlock == [todo.id: planned])
        #expect(await center.reminders == [todo.id: planned], "Erinnerung ohne Block bleibt geplant")
    }

    @Test func checkingEditingAndTrashingFollowTheBlocks() async throws {
        let first = Self.todo("Brot")
        let second = Self.todo("Milch")
        let pageID = try await page("Einkauf", [first, second])
        reminders.start()
        await reminders.settle()
        _ = try await reminders.set(blockID: first.id, pageID: pageID, date: later)
        _ = try await reminders.set(blockID: second.id, pageID: pageID, date: later)

        var checked = first
        checked.properties.isChecked = true
        var edited = second
        edited.text = "Hafermilch"
        try await store.applyEdits(pageID, BlockEdits(upserts: [checked, edited], order: [first.id, second.id]))
        try await waitFor {
            let planned = await center.reminders
            return planned.keys.sorted() == [second.id] && planned[second.id]?.text == "Hafermilch"
        }
        // Die Zentrale ist vor `byBlock` fertig; erst den Abgleich zu Ende laufen lassen.
        await reminders.settle()
        #expect(reminders.byBlock.keys.sorted() == [second.id])

        try await store.trash(pageID)
        try await waitFor { await center.reminders.isEmpty }
        await reminders.settle()
        #expect(reminders.byBlock.isEmpty)
    }

    /// Entfernen, während der Abgleich die geplanten schon gelesen hat: Der Abgleich darf
    /// die Erinnerung danach nicht zurückbringen.
    @Test func removingWaitsForARunningReconcile() async throws {
        let slow = SlowReminderCenter()
        let reminders = Reminders(store: store, center: slow, delay: .milliseconds(10))
        let todo = Self.todo("Anrufen")
        let pageID = try await page("Heute", [todo])
        await slow.schedule(Reminder(blockID: todo.id, pageID: pageID, date: later, text: "Anrufen", pageTitle: "Heute"))

        reminders.start()
        try await waitFor { await slow.reads > 0 }
        await reminders.remove(blockID: todo.id)
        await reminders.settle()
        #expect(await slow.inner.reminders.isEmpty)
        #expect(reminders.byBlock.isEmpty)
    }

    @Test func notificationTitleIsOneLineWithFallback() {
        #expect(SystemReminderCenter.title("Brot\u{2028}und Milch") == "Brot und Milch")
        #expect(SystemReminderCenter.title(" ") == "To-do without text")
    }

    @Test func triggerKeepsTheSeconds() throws {
        let date = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / 60).rounded(.up) * 60 + 3600 + 40)
        #expect(SystemReminderCenter.trigger(at: date).nextTriggerDate() == date)
    }

    #if canImport(AppKit)
    @Test func onlyOpenTodosInAnEditableEditor() {
        let open = EditorBlock(kind: .todo, text: "Offen")
        let done = EditorBlock(kind: .todo, text: "Erledigt", isChecked: true)
        #expect(ReminderRequest.remindable(open, allowsEditing: true) == open)
        #expect(ReminderRequest.remindable(done, allowsEditing: true) == nil)
        #expect(ReminderRequest.remindable(open, allowsEditing: false) == nil)
        #expect(ReminderRequest.remindable(EditorBlock(kind: .paragraph, text: "Absatz"), allowsEditing: true) == nil)
    }

    @Test func suggestionIsTomorrowAtNine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 22, minute: 30)))
        let expected = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9)))
        #expect(ReminderView.suggestion(now: now, calendar: calendar) == expected)
    }
    #endif
}

/// Liest die geplanten sofort, gibt sie aber erst nach einer Pause zurück: So hat der
/// Abgleich einen alten Stand, während der Test entfernt.
private actor SlowReminderCenter: ReminderCenter {
    let inner = MemoryReminderCenter()
    private(set) var reads = 0

    func authorize() async throws -> Bool { true }

    func pending() async -> [Reminder] {
        let planned = await inner.pending()
        reads += 1
        try? await Task.sleep(for: .milliseconds(300))
        return planned
    }

    func schedule(_ reminder: Reminder) async { await inner.schedule(reminder) }
    func cancel(_ blockIDs: [UUID]) async { await inner.cancel(blockIDs) }
}
