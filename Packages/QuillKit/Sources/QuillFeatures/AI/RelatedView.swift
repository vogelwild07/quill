#if canImport(AppKit)
import AppKit
import OSLog
import QuillAI
import QuillEditorCore
import QuillModel
import SwiftUI

/// Anfrage „Seite › Verwandte Seiten …“.
struct RelatedRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    /// Titel wie gespeichert, leer bei „Ohne Titel“.
    let title: String
}

/// Seiten zum selben Thema (16.5, ADR-032).
@MainActor
@Observable
final class RelatedModel {
    enum Phase: Equatable {
        case working
        case done([TermSearch.Match])
        case failed(String)
    }

    private(set) var phase = Phase.working
    @ObservationIgnored private let request: RelatedRequest
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let model: any TextModel

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "ai")

    init(request: RelatedRequest, store: PageStore, model: any TextModel) {
        self.request = request
        self.store = store
        self.model = model
    }

    func run() async {
        phase = .working
        // Was im Editor noch wartet, gehört zur Seite.
        await EditorPersistenceBridge.flushAll(pageID: request.pageID)
        do {
            let finder = RelatedPageFinder(model: model, store: store)
            phase = .done(try await finder.related(to: request.pageID, title: request.title))
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Verwandte Seiten gescheitert: \(String(describing: error), privacy: .public)")
            phase = .failed(Self.message(error))
        }
    }

    static func message(_ error: any Error) -> String {
        if case RelatedPageFinder.Failure.empty = error {
            return String(localized: "Die Seite enthält noch keinen Text, zu dem es verwandte Seiten geben könnte.", bundle: .module)
        }
        return AIProblem.message(error, fallback: String(localized: "Die Suche nach verwandten Seiten ist gescheitert.", bundle: .module))
    }
}

/// Blatt mit verwandten Seiten: gemeinsame Begriffe sehen, Seite öffnen.
struct RelatedView: View {
    let request: RelatedRequest
    @State var model: RelatedModel
    /// Öffnet die Seite und schließt das Blatt.
    let open: (UUID) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verwandte Seiten", bundle: .module)
                    .font(.headline)
                Text(Self.title(request.title))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            content
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            Text("Vorgeschlagen vom Sprachmodell auf diesem Mac anhand gemeinsamer Begriffe.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Schließen", bundle: .module), action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await model.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Suche verwandte Seiten …", bundle: .module)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("related.progress")
        case .done(let pages) where pages.isEmpty:
            Text("Keine verwandten Seiten gefunden.", bundle: .module)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("related.empty")
        case .done(let pages):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pages) { page in
                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                open(page.pageID)
                            } label: {
                                Label(Self.title(page.title), systemImage: "doc.text")
                            }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("related.page")
                            Text("Gemeinsam: \(page.terms.formatted(.list(type: .and)))", bundle: .module)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("related.terms")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
        case .failed(let message):
            ProblemLabel(message: message)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("related.problem")
        }
    }

    static func title(_ title: String) -> String {
        title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : title
    }
}
#endif
