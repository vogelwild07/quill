import Foundation
import Testing
@testable import QuillFeatures

extension PerformanceSuites {
    /// Seitenbaum der Sidebar aus 5000 Seiten (zehn Kinder pro Seite, ein Viertel
    /// Favoriten): p95 von 20.
    @Suite("Sidebar")
    struct Sidebar {
        @Test func pageTreeBuild() {
            var ids: [UUID] = []
            let entries = (0..<5000).map { index in
                let id = UUID()
                ids.append(id)
                return PageTree.Entry(
                    id: id, parentID: index == 0 ? nil : ids[(index - 1) / 10],
                    title: "Seite \(index)", icon: nil,
                    sortKey: String(format: "a%04d", index), createdAt: .now,
                    isFavorite: index % 4 == 0, favoriteSortKey: index % 4 == 0 ? String(format: "a%04d", index) : nil
                )
            }.shuffled()
            let values = Performance.repeated {
                var samples: [Double] = []
                for _ in 0..<20 {
                    let start = ContinuousClock.now
                    let tree = PageTree.build(entries)
                    _ = PageTree.favorites(entries, in: tree)
                    samples.append(Performance.milliseconds(ContinuousClock.now - start))
                }
                return Performance.p95(samples)
            }
            Performance.report("pageTreeBuild", runs: values)
        }
    }
}
