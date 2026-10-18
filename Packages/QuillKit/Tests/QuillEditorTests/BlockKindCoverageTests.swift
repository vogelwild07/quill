import Foundation
import QuillModel
import Testing
@testable import QuillEditor

/// Jede Blockart muss überall behandelt werden, wo Blöcke ankommen. Eine neue Art in
/// `BlockKind` lässt diese Tests scheitern, bis sie in Renderer, Slash-Menü und
/// Markdown berücksichtigt ist (oder bewusst in `notInSlashMenu` steht).
@Suite("BlockKind: jede Art überall behandelt")
struct BlockKindCoverageTests {
    /// Arten, die (noch) nicht im Slash-Menü stehen, mit Grund.
    /// `.image`: braucht die Asset-Anbindung des Bild-Blocks (Phase 4).
    static let notInSlashMenu: Set<BlockKind> = [.image]

    private static func sample(_ kind: BlockKind) -> EditorBlock {
        EditorBlock(kind: kind, text: kind.isAtomic ? "" : "Inhalt")
    }

    @Test(arguments: BlockKind.allCases)
    func rawValueSurvivesStoreAndSnapshot(_ kind: BlockKind) {
        #expect(BlockKind(rawValue: kind.rawValue) == kind)
        let block = Self.sample(kind)
        #expect(EditorBlock(snapshot: block.snapshot).kind == kind)
    }

    @Test(arguments: BlockKind.allCases)
    func rendererKeepsKind(_ kind: BlockKind) {
        // Mit Nachbarn, damit atomare Blöcke nicht am Rand stehen.
        let blocks = [EditorBlock(text: "davor"), Self.sample(kind), EditorBlock(text: "danach")]
        let (parsed, repaired) = BlockRenderer.parse(BlockRenderer.render(blocks[...], ordinals: [:]))
        #expect(parsed.map(\.kind) == blocks.map(\.kind))
        #expect(parsed[1].text == blocks[1].text)
        #expect(repaired.isEmpty)
    }

    @Test func slashMenuOffersEveryKind() {
        let offered = SlashCommand.all.map(\.kind)
        #expect(offered.count == Set(offered).count, "Blockart doppelt im Slash-Menü")
        #expect(Set(offered).isDisjoint(with: Self.notInSlashMenu))
        #expect(Set(offered).union(Self.notInSlashMenu) == Set(BlockKind.allCases))
    }

    @Test(arguments: BlockKind.allCases)
    func markdownExportsKind(_ kind: BlockKind) {
        let block = Self.sample(kind)
        let markdown = MarkdownSerializer.markdown(for: EditorDocument(blocks: [block]), blocks: 0..<1)
        #expect(!markdown.isEmpty)
        if !kind.isAtomic {
            #expect(markdown.contains("Inhalt"))
        }
    }

    @Test func markdownDistinguishesEveryKind() {
        let outputs = BlockKind.allCases.map { kind in
            MarkdownSerializer.markdown(for: EditorDocument(blocks: [Self.sample(kind)]), blocks: 0..<1)
        }
        #expect(Set(outputs).count == BlockKind.allCases.count)
    }
}
