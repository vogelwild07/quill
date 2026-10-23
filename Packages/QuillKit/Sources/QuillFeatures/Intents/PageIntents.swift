import AppIntents
import Foundation
import QuillEditorCore
import QuillModel

/// Kurzbefehle und Siri (15.1, ADR-033). Die App nimmt sie über ihr eigenes
/// `AppIntentsPackage` auf.
public struct QuillFeaturesIntents: AppIntentsPackage {}

/// Verbindung der Kurzbefehle zum offenen Store.
@MainActor
public enum PageIntentStore {
    /// Intern statt privat, damit Tests die Aktionen ohne App ausführen können.
    static var store: PageStore?

    /// Nach dem Öffnen des Stores.
    public static func connect(_ persistence: QuillPersistence) {
        store = persistence.store
    }

    static func actions() throws -> PageIntentActions {
        guard let store else { throw PageIntentError.notReady }
        return PageIntentActions(store: store)
    }
}

enum PageIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// Store noch nicht offen (Rückfrage vor einer Migration).
    case notReady

    var localizedStringResource: LocalizedStringResource {
        .translated(String(localized: "Quill ist noch nicht bereit. Öffne Quill und versuch es noch einmal.", bundle: .module))
    }
}

extension PageIntentActions.Failure: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .pageMissing: .translated(String(localized: "Die Seite gibt es nicht mehr.", bundle: .module))
        case .emptyText: .translated(String(localized: "Es gibt keinen Text zum Hinzufügen.", bundle: .module))
        }
    }
}

extension LocalizedStringResource {
    /// Schon in Quill übersetzter Text: Das System schlägt ihn nicht im Bundle der App nach
    /// (die Texte stehen im Katalog von QuillFeatures).
    static func translated(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource(stringLiteral: text)
    }
}

public struct PageEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Seite"
    public static let defaultQuery = PageQuery()

    public let id: UUID
    /// Wie gespeichert, leer bei „Ohne Titel“.
    @Property(title: "Titel") public var title: String

    init(_ page: PageIntentActions.PageReference) {
        id = page.id
        title = page.title
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(PageLabel.title(title))")
    }
}

public struct PageQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [PageEntity] {
        try await PageIntentStore.actions().pages(identifiers).map(PageEntity.init)
    }

    public func entities(matching string: String) async throws -> [PageEntity] {
        try await PageIntentStore.actions().pages(matching: string).map(PageEntity.init)
    }

    public func suggestedEntities() async throws -> [PageEntity] {
        try await PageIntentStore.actions().suggestedPages().map(PageEntity.init)
    }
}

public struct NewPageIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Neue Seite"
    public static let description = IntentDescription("Legt in Quill eine neue Seite an und öffnet sie.")

    @Parameter(title: "Titel")
    public var pageTitle: String?

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    public var text: String?

    public func perform() async throws -> some IntentResult & ReturnsValue<PageEntity> & OpensIntent {
        let page = PageEntity(try await PageIntentStore.actions().createPage(title: pageTitle, text: text))
        return .result(value: page, opensIntent: OpenPageIntent(target: page))
    }
}

public struct AddToPageIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Zu Seite hinzufügen"
    public static let description = IntentDescription(
        "Hängt jede Zeile als Block an eine Seite an. Endet die Seite mit einer Liste, wird sie fortgesetzt."
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Seite")
    public var page: PageEntity

    @Parameter(title: "Text", requestValueDialog: "Was soll auf die Seite?")
    public var text: String

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$text) zu \(\.$page) hinzufügen")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let actions = try PageIntentStore.actions()
        // Was im Editor noch wartet, gehört zur Seite: sonst fehlt die Liste, die fortgesetzt wird.
        await EditorPersistenceBridge.flushAll(pageID: page.id)
        try await actions.append(text, to: page.id)
        let title = PageLabel.title(page.title)
        return .result(dialog: IntentDialog(.translated(String(localized: "Zu „\(title)“ hinzugefügt.", bundle: .module))))
    }
}

/// Öffnet die Seite im vordersten Fenster (`PageJumpRouter`), sonst in einem neuen.
public struct OpenPageIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Seite öffnen"

    @Parameter(title: "Seite")
    public var target: PageEntity

    public init() {}

    public init(target: PageEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        #if canImport(AppKit)
        PageJumpRouter.shared.open(target.id)
        #endif
        return .result()
    }
}
