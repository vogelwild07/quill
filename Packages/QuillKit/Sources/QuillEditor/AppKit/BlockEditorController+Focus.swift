#if canImport(AppKit)
import AppKit
import QuillDesign

/// Fokus-Modus (Phase 18.1, `EditorFocusSettings`): Die Zeile mit dem Cursor bleibt in
/// der Mitte des Fensters (Schreibmaschinen-Scrollen), alle Blöcke außer denen mit
/// Cursor oder Auswahl und der Kopf werden in Richtung Theme-Hintergrund abgedunkelt
/// (`ResolvedPalette.dimmedAlpha`). Abgedunkelt wird nur, solange der Text den Fokus
/// hat; im Titel oder in der Sidebar ist alles normal. Ändert keinen Text, ist also
/// kein Undo-Schritt und kein Speichern.
extension BlockEditorController {
    func observeFocusMode() {
        let apply: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFocusMode() }
        }
        // Theme, „Kontrast erhöhen“ und Darstellung führen den Kopf über `applyTheme`
        // bzw. `viewDidChangeEffectiveAppearance` nach (`updateHeaderDimming`).
        focusObservations = [NotificationObservation(EditorFocusSettings.didChange, object: nil, using: apply)]
        // Fenstergröße geändert: Cursor wieder in die Mitte. Den Platz unter dem Text
        // rechnet `BlockTextView.setFrameSize` neu, das AppKit dabei aufruft (Autoresizing).
        scrollView.contentView.postsFrameChangedNotifications = true
        focusObservations.append(NotificationObservation(NSView.frameDidChangeNotification, object: scrollView.contentView) { [weak self] _ in
            MainActor.assumeIsolated { self?.visibleSizeDidChange() }
        })
        applyFocusMode()
    }

    func visibleSizeDidChange() {
        guard isFocusModeEnabled else { return }
        centerCaret(animated: false)
    }

    var isFocusModeEnabled: Bool { EditorFocusSettings.shared.isEnabled }

    /// Fokus-Modus ein- oder ausgeschaltet: Platz unter dem Text, Abdunkeln, Cursor mittig.
    func applyFocusMode() {
        textView.isTypewriterScrolling = isFocusModeEnabled
        updateFocusedBlocks()
        if isFocusModeEnabled { centerCaret(animated: false) }
    }

    /// Nach Auswahl- oder Textänderungen, einmal pro Durchlauf der Run-Loop: Dann sind
    /// die Absätze abgeglichen und das Layout steht.
    func scheduleFocusUpdate() {
        guard isFocusModeEnabled, !isFocusUpdateScheduled else { return }
        isFocusUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isFocusUpdateScheduled = false
                self.updateFocusedBlocks()
                // Beim Ziehen mit der Maus nicht scrollen; das folgt nach dem Loslassen.
                if NSEvent.pressedMouseButtons == 0 { self.centerCaret(animated: false) }
            }
        }
    }

    /// Nach einem Klick: Cursor sanft in die Mitte, bei „Bewegung reduzieren“ sofort.
    func focusMouseSelectionDidEnd() {
        guard isFocusModeEnabled else { return }
        updateFocusedBlocks()
        centerCaret(animated: !QuillDesign.Motion.isReduced)
    }

    // MARK: Abdunkeln

    /// Blöcke mit Cursor oder Auswahl; `nil`, wenn nichts abgedunkelt wird.
    var currentFocusedBlocks: Set<UUID>? {
        guard isFocusModeEnabled, let window = textView.window, window.firstResponder === textView,
              document.count > 0 else { return nil }
        let selection = textView.selectedRange()
        let first = blockIndex(atCharacter: selection.location)
        let last = blockIndex(atCharacter: max(selection.location, NSMaxRange(selection) - 1))
        return Set((first...last).map { document[$0].id })
    }

    /// Gleicht die abgedunkelten Blöcke ab und layoutet nur die geänderten neu.
    func updateFocusedBlocks() {
        let new = currentFocusedBlocks
        let old = layoutDelegate.focusedBlocks
        guard new != old else { return updateHeaderDimming() }
        layoutDelegate.focusedBlocks = new
        guard let manager = textView.textLayoutManager else { return }
        if let old, let new {
            let changed = old.symmetricDifference(new)
            for (index, block) in document.blocks.enumerated() where changed.contains(block.id) {
                if let range = textRange(for: paragraphRange(ofBlock: index)) { manager.invalidateLayout(for: range) }
            }
        } else {
            manager.invalidateLayout(for: manager.documentRange)
        }
        textView.needsLayout = true
        textView.needsDisplay = true
        updateHeaderDimming()
    }

    /// Kopf mit der Deckkraft des Fließtexts, solange Blöcke abgedunkelt sind; nicht,
    /// solange er nur den Platzhalter „Ohne Titel“ zeigt (Systemfarbe, abgedunkelt
    /// unter 3 : 1). Nach Theme- oder Darstellungswechsel erneut aufrufen.
    func updateHeaderDimming() {
        guard let header else { return }
        let dims = layoutDelegate.focusedBlocks != nil && !headerShowsPlaceholder
        let alpha = dims ? EditorThemeState.dimmedAlpha(for: textView.effectiveAppearance) : 1
        if header.alphaValue != alpha { header.alphaValue = alpha }
    }

    private func textRange(for range: NSRange) -> NSTextRange? {
        guard let content = textView.textLayoutManager?.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    // MARK: Schreibmaschinen-Scrollen

    /// Scrollt so, dass die Zeile mit dem Cursor in der Mitte des sichtbaren Bereichs
    /// steht, soweit der Text das zulässt (oben bleibt der Kopf am Anfang). Nicht bei
    /// einer Auswahl und nicht bei markiertem Text (IME).
    func centerCaret(animated: Bool) {
        guard isFocusModeEnabled, textView.window != nil, !textView.hasMarkedText() else { return }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return }
        let clip = scrollView.contentView
        // Absätze außerhalb des sichtbaren Bereichs hat TextKit nur geschätzt; nach dem
        // Sprung stehen sie fest, und die Zeile kann sich um einige Punkte verschieben.
        // Ohne Animation deshalb bis zu zweimal nachmessen.
        var origin = clip.bounds.origin
        for _ in 0..<(animated ? 1 : 3) {
            guard let caret = caretRect(at: selection.location) else { return }
            let insets = clip.contentInsets
            let visibleHeight = clip.bounds.height - insets.top - insets.bottom
            let minY = -insets.top
            let maxY = max(minY, textView.frame.height - clip.bounds.height + insets.bottom)
            let y = min(max(caret.midY - insets.top - visibleHeight / 2, minY), maxY).rounded()
            guard abs(origin.y - y) >= 1 else { break }
            origin.y = y
            if !animated {
                clip.setBoundsOrigin(origin)
                textView.layoutSubtreeIfNeeded()
            }
        }
        if animated, abs(clip.bounds.origin.y - origin.y) >= 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = QuillDesign.Motion.typewriterScrollDuration
                clip.animator().setBoundsOrigin(origin)
            }
        }
        scrollView.reflectScrolledClipView(clip)
    }

    /// Rechteck der Zeile mit dem Cursor in Koordinaten der Text-View.
    func caretRect(at location: Int) -> CGRect? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let target = content.location(content.documentRange.location, offsetBy: location) else { return nil }
        var rect: CGRect?
        manager.enumerateTextSegments(in: NSTextRange(location: target), type: .selection, options: [.rangeNotRequired]) { _, frame, _, _ in
            rect = frame
            return false
        }
        return rect?.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }
}
#endif
