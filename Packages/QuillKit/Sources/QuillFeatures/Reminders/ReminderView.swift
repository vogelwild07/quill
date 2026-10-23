#if canImport(AppKit)
import AppKit
import OSLog
import QuillDesign
import QuillEditor
import QuillEditorCore
import QuillModel
import SwiftUI

/// Anfrage „Format › Erinnerung …“: das To-do an der Einfügemarke und seine Seite.
struct ReminderRequest: Identifiable {
    let id = UUID()
    let pageID: UUID?
    /// `nil`, wenn die Einfügemarke in keinem bearbeitbaren, offenen To-do steht.
    let block: EditorBlock?

    @MainActor
    init(pageID: UUID?, focusedIn window: NSWindow?) {
        self.pageID = pageID
        let editor = BlockEditorController.focused(in: window)
        let cursor = editor?.cursorBlockID
        let block = editor?.document.blocks.first { $0.id == cursor }
        self.block = Self.remindable(block, allowsEditing: editor?.allowsEditing == true)
    }

    /// Nur ein offenes To-do in einem bearbeitbaren Editor.
    static func remindable(_ block: EditorBlock?, allowsEditing: Bool) -> EditorBlock? {
        allowsEditing && block?.kind == .todo && block?.isChecked == false ? block : nil
    }
}

/// Blatt für die Erinnerung an ein To-do (15.4, ADR-033).
struct ReminderView: View {
    let request: ReminderRequest
    let reminders: Reminders
    let dismiss: () -> Void
    @State private var date: Date
    @State private var problem: String?
    @State private var isWorking = false

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "reminders")

    init(request: ReminderRequest, reminders: Reminders, dismiss: @escaping () -> Void) {
        self.request = request
        self.reminders = reminders
        self.dismiss = dismiss
        _date = State(initialValue: request.block.flatMap { reminders.byBlock[$0.id]?.date } ?? Self.suggestion())
    }

    /// Morgen um 9:00.
    static func suggestion(now: Date = .now, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var existing: Reminder? {
        request.block.flatMap { reminders.byBlock[$0.id] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Erinnerung", bundle: .module)
                    .font(.headline)
                if let block = request.block {
                    Text(block.text.isEmpty ? String(localized: "To-do ohne Text", bundle: .module) : block.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if request.block != nil, request.pageID != nil {
                DatePicker(selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute]) {
                    Text("Zeitpunkt", bundle: .module)
                }
                .accessibilityIdentifier("reminder.date")
                Text(problem ?? String(localized: "Eine Mitteilung auf diesem Mac erinnert dich daran.", bundle: .module))
                    .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder.message")
            } else {
                Text("Setze die Einfügemarke in ein offenes To-do.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reminder.message")
            }
            HStack {
                if existing != nil {
                    Button(role: .destructive) {
                        Task { await remove() }
                    } label: {
                        Text("Entfernen", bundle: .module)
                    }
                    .accessibilityIdentifier("reminder.remove")
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Abbrechen", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    Task { await schedule() }
                } label: {
                    Text("Erinnern", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request.block == nil || request.pageID == nil || isWorking)
                .accessibilityIdentifier("reminder.schedule")
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
    }

    private func schedule() async {
        guard let block = request.block, let pageID = request.pageID else { return }
        isWorking = true
        defer { isWorking = false }
        // Ein gerade getipptes To-do muss im Store stehen.
        await EditorPersistenceBridge.flushAll(pageID: pageID)
        do {
            if try await reminders.set(blockID: block.id, pageID: pageID, date: date) {
                dismiss()
            } else {
                problem = String(localized: "Quill darf keine Mitteilungen senden. Erlaube sie in den Systemeinstellungen unter „Mitteilungen“.", bundle: .module)
            }
        } catch Reminders.Failure.past {
            problem = String(localized: "Wähle einen Zeitpunkt in der Zukunft.", bundle: .module)
        } catch {
            Self.logger.error("Erinnerung nicht geplant: \(String(describing: error), privacy: .public)")
            problem = String(localized: "Die Erinnerung konnte nicht geplant werden.", bundle: .module)
        }
    }

    private func remove() async {
        guard let block = request.block else { return }
        await reminders.remove(blockID: block.id)
        dismiss()
    }
}

/// Popover zum Zeichen am To-do: Zeitpunkt und „Entfernen“.
struct ReminderMarkerView: View {
    let date: Date?
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QuillDesign.SyncNotice.sectionSpacing) {
            // Zeitpunkt in der Überschrift: Normaler Text hält auf dem Glas des Popovers den
            // Kontrast nicht sicher.
            Group {
                if let date {
                    Text("Erinnerung am \(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))", bundle: .module)
                } else {
                    Text("Erinnerung", bundle: .module)
                }
            }
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("reminder.marker.date")
            Button(String(localized: "Erinnerung entfernen", bundle: .module), action: remove)
                .accessibilityIdentifier("reminder.marker.remove")
        }
        .padding(QuillDesign.SyncNotice.popoverPadding)
        .frame(width: QuillDesign.SyncNotice.restoredWidth, alignment: .leading)
    }
}
#endif
