#if canImport(AppKit)
import AppKit
import QuillDesign
import Testing

/// „Bewegung reduzieren“ (Befund A13 aus Phase 7.3): Zeilen blenden statt zu
/// gleiten, Hinweise verschwinden ohne Animation.
@Suite("Design: Bewegung")
struct MotionTests {
    @Test func rowsFadeInsteadOfSlidingWhenMotionIsReduced() {
        #expect(QuillDesign.Motion.rowAnimation(.slideDown, reduceMotion: false) == .slideDown)
        #expect(QuillDesign.Motion.rowAnimation(.slideUp, reduceMotion: false) == .slideUp)
        #expect(QuillDesign.Motion.rowAnimation(.slideDown, reduceMotion: true) == .effectFade)
        #expect(QuillDesign.Motion.rowAnimation(.slideUp, reduceMotion: true) == .effectFade)
    }

    @Test func noticeHidesWithoutFadeWhenMotionIsReduced() {
        #expect(QuillDesign.Motion.fadeOutDuration(reduceMotion: false) == 0.3)
        #expect(QuillDesign.Motion.fadeOutDuration(reduceMotion: true) == 0)
    }
}
#endif
