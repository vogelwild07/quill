#if canImport(AppKit)
import QuillEditor
import QuillEditorCore
import QuillModel
import QuillSync
import SwiftData
import SwiftUI

/// Fenster „Zeitreise …“ (⌥⌘Y, 12.3, ADR-031): eins je Seite. `QuillApp` legt die
/// Szene an; `QuillCommands` öffnet sie mit der ausgewählten Seite.
public struct TimeTravelScene: Scene {
    public static let windowID = "timeTravel"
    let persistence: QuillPersistence?

    public init(persistence: QuillPersistence?) {
        self.persistence = persistence
    }

    public var body: some Scene {
        WindowGroup(String(localized: "Zeitreise", bundle: .module), id: Self.windowID, for: UUID.self) { $pageID in
            if let persistence, let pageID {
                TimeTravelView(pageID: pageID, persistence: persistence)
                    .modelContainer(persistence.container)
                    .environment(\.pageStore, persistence.store)
            }
        }
        .defaultSize(width: 900, height: 640)
    }
}

struct TimeTravelView: View {
    let pageID: UUID
    let persistence: QuillPersistence

    @Query private var pages: [Page]
    @State private var model: TimeTravelModel

    init(pageID: UUID, persistence: QuillPersistence) {
        self.pageID = pageID
        self.persistence = persistence
        _pages = Query(filter: #Predicate<Page> { $0.id == pageID })
        let history = persistence.history
        _model = State(initialValue: TimeTravelModel(pageID: pageID, store: persistence.store) { await history.flush() })
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(model.days, id: \.self, selection: $model.selectedDay) { day in
                Text(Self.label(for: day.day))
                    .accessibilityIdentifier("timeTravel.day")
            }
            .accessibilityIdentifier("timeTravel.days")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "Auswahl zurückholen", bundle: .module), systemImage: "arrow.uturn.backward") {
                    Task { await model.restoreSelection() }
                }
                .help(String(localized: "Holt die markierten Absätze dieses Tages in die Seite zurück.", bundle: .module))
                .disabled(!model.canRestore)
                .accessibilityIdentifier("timeTravel.restore")
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var detail: some View {
        if pages.first == nil || pages.first?.trashedAt != nil {
            EmptyStateView(.pageNotFound, id: "timeTravel.notFound")
        } else {
            switch model.phase {
            case .loading:
                ProgressView()
            case .failed:
                EmptyStateView(.historyUnreadable, id: "timeTravel.failed")
            case .ready where model.days.isEmpty:
                EmptyStateView(.noHistory, id: "timeTravel.empty")
            case .ready:
                VStack(spacing: 0) {
                    if model.restoreFailed {
                        ProblemLabel(message: String(localized: "Zurückholen gescheitert. Quill versucht es weiter.", bundle: .module))
                            .padding(8)
                    }
                    BlockEditorView(controller: model.controller)
                }
            }
        }
    }

    private var title: String {
        let page = PageLabel.title(pages.first?.title ?? "")
        return String(localized: "Zeitreise: \(page)", bundle: .module)
    }

    /// „Heute“, „Gestern“, sonst Wochentag und Datum.
    static func label(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Heute", bundle: .module) }
        if calendar.isDateInYesterday(day) { return String(localized: "Gestern", bundle: .module) }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}
#endif
