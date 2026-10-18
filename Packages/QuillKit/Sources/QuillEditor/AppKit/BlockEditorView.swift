#if canImport(AppKit)
import AppKit
import SwiftUI

/// SwiftUI-Hülle um den Block-Editor.
public struct BlockEditorView: NSViewRepresentable {
    private let controller: BlockEditorController

    public init(controller: BlockEditorController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSScrollView {
        controller.scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
#endif
