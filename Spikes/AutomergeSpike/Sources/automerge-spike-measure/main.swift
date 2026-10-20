import AutomergeSpike
import Foundation
import QuillEditor

// Nur auf dem Mac: misst mit frischen Prozessen (`Process`). Auf iOS baut nur die
// Bibliothek des Spikes mit.
#if canImport(AppKit)

// Misst Automerge gegen die Kriterien aus ADR-026. Nur optimiert sinnvoll:
//   swift run -c release automerge-spike-measure [laden|abgleich|speicher|alles]
// Die App-Größe misst Scripts/spike-app-size.sh im Spike-Ordner.

let clock = ContinuousClock()

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
}

func format(_ value: Double, _ digits: Int = 1) -> String {
    String(format: "%.\(digits)f", value)
}

func megabytes(_ bytes: Int) -> String {
    format(Double(bytes) / 1_048_576, 2) + " MB"
}

/// Lädt eine gespeicherte Seite vollständig: Datei lesen, Dokument laden, Blöcke für
/// den Editor erzeugen.
func loadPage(_ url: URL) throws -> Int {
    let data = try Data(contentsOf: url)
    return try PageCRDT(bytes: data).blocks().count
}

let arguments = CommandLine.arguments.dropFirst()

// Kalter Lauf in einem frischen Prozess: `load-once <Datei>` gibt die Zeit in ms aus.
if arguments.first == "load-once", let path = arguments.dropFirst().first {
    let start = clock.now
    _ = try loadPage(URL(filePath: path))
    print(format(milliseconds(clock.now - start), 3))
    exit(0)
}

let mode = arguments.first ?? "alles"
let directory = FileManager.default.temporaryDirectory.appending(path: "QuillAutomergeSpike-\(ProcessInfo.processInfo.processIdentifier)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

func coldLoad(_ url: URL, runs: Int) throws -> [Double] {
    try (0..<runs).map { _ in
        let process = Process()
        process.executableURL = URL(filePath: CommandLine.arguments[0])
        process.arguments = ["load-once", url.path(percentEncoded: false)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let value = Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SpikeError.malformed("load-once ohne Ergebnis")
        }
        return value
    }
}

/// Eine Seite mit Geschichte, wie sie die Messungen zum Laden und Abgleichen nutzen.
let cases: [(String, Int, CommitGranularity)] = [
    ("5.000 Wörter", 5_000, .perWord),
    ("5.000 Wörter", 5_000, .perKeystroke),
    ("Schwerfall 15.000 Wörter", 15_000, .perWord),
    ("Schwerfall 15.000 Wörter", 15_000, .perKeystroke),
]

if mode == "laden" || mode == "alles" {
    print("## Laden einer Seite mit Geschichte (Kriterium < 50 ms)\n")
    print("| Fall | Blöcke | Zeichen | Tastendrücke | Änderungen | Datei | Median | p95 | max | kalt (Median von 5) | ohne Zuordnung (Median) | 1 Wort als Änderung |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for (index, (name, words, granularity)) in cases.enumerated() {
        var simulator = try PageHistorySimulator(words: words, granularity: granularity, seed: UInt64(100 + index))
        let page = try simulator.run()
        let data = page.document.save()
        let url = directory.appending(path: "page-\(index).automerge")
        try data.write(to: url)
        let blocks = try page.blocks()
        let characters = blocks.reduce(0) { $0 + $1.length }
        let changes = page.document.getHistory().count

        // Größe einer Änderung, wie sie als `.changes`-Datei im Ordner landet.
        let heads = page.document.heads()
        let last = try page.textObject(at: page.blockCount - 1)
        try page.document.spliceText(obj: last, start: 0, delete: 0, value: "Nachtrag ")
        page.document.commitWith()
        let changeBytes = try page.document.encodeChangesSince(heads: heads).count

        for _ in 0..<3 { _ = try loadPage(url) }
        var warm: [Double] = []
        for _ in 0..<50 {
            let start = clock.now
            _ = try loadPage(url)
            warm.append(milliseconds(clock.now - start))
        }
        var documentOnly: [Double] = []
        for _ in 0..<20 {
            let start = clock.now
            _ = try PageCRDT(bytes: Data(contentsOf: url))
            documentOnly.append(milliseconds(clock.now - start))
        }
        let cold = try coldLoad(url, runs: 5)
        print(
            "| \(name), Commit \(granularity.rawValue) | \(blocks.count) | \(characters) | \(simulator.keystrokes) (\(simulator.deletions) gelöscht) | \(changes) | \(format(Double(data.count) / 1024)) KB | \(format(percentile(warm, 0.5), 2)) ms | \(format(percentile(warm, 0.95), 2)) ms | \(format(warm.max()!, 2)) ms | \(format(percentile(cold, 0.5), 2)) ms | \(format(percentile(documentOnly, 0.5), 2)) ms | \(changeBytes) B |"
        )
    }
    print()
}

if mode == "abgleich" || mode == "alles" {
    print("## Abgleich einer Seite im Hintergrund (Kriterium < 250 ms, auch im Schwerfall)\n")
    print("Ein anderes Gerät hat 50 Wörter in einen Block getippt und einen Block angefügt (Commit pro Wort). Gemessen: Datei lesen, Dokument laden, Änderungen anwenden, Blöcke erzeugen, speichern.\n")
    print("| Fall | eingehende Änderungen | Median | p95 | max |")
    print("|---|---|---|---|---|")
    for (index, (name, words, granularity)) in cases.enumerated() {
        var simulator = try PageHistorySimulator(words: words, granularity: granularity, seed: UInt64(100 + index))
        let page = try simulator.run()
        let url = directory.appending(path: "sync-\(index).automerge")
        try page.document.save().write(to: url)
        let other = try page.fork()
        let heads = other.document.heads()
        let text = try other.textObject(at: other.blockCount / 2)
        for number in 0..<50 {
            try other.document.spliceText(obj: text, start: 0, delete: 0, value: "wort\(number) ")
            other.document.commitWith()
        }
        try other.insertBlock(EditorBlock(text: "Vom anderen Gerät"), at: other.blockCount)
        other.document.commitWith()
        let incoming = try other.document.encodeChangesSince(heads: heads)
        let output = directory.appending(path: "sync-\(index)-out.automerge")
        var times: [Double] = []
        for run in 0..<23 {
            let start = clock.now
            let local = try PageCRDT(bytes: Data(contentsOf: url))
            _ = try local.document.applyEncodedChangesWithPatches(encoded: incoming)
            let blocks = try local.blocks()
            try local.document.save().write(to: output)
            let time = milliseconds(clock.now - start)
            precondition(blocks.count == page.blockCount + 1)
            if run >= 3 { times.append(time) }
        }
        print("| \(name), Commit \(granularity.rawValue) | 51 (\(incoming.count) B) | \(format(percentile(times, 0.5), 2)) ms | \(format(percentile(times, 0.95), 2)) ms | \(format(times.max()!, 2)) ms |")
    }
    print()
}

if mode == "speicher" || mode == "alles" {
    print("## 1.000 Seiten mit Geschichte (Kriterium < 50 MB zusätzlich)\n")
    print("Mischung: 700 × 500 Wörter, 250 × 2.000 Wörter, 50 × 5.000 Wörter.\n")
    print("| Commit | Automerge gesamt | je Seite (Mittel) | größte Seite | Inhalt als JSON (ohne Geschichte) | Faktor | Dauer Erzeugen |")
    print("|---|---|---|---|---|---|---|")
    let sizes = Array(repeating: 500, count: 700) + Array(repeating: 2_000, count: 250) + Array(repeating: 5_000, count: 50)
    for granularity in CommitGranularity.allCases {
        let start = clock.now
        let results = UnsafeMutableBufferPointer<(Int, Int)>.allocate(capacity: sizes.count)
        defer { results.deallocate() }
        // Jede Seite ist ein eigenes Dokument; parallel erzeugen spart nur Wartezeit.
        nonisolated(unsafe) let buffer = results
        DispatchQueue.concurrentPerform(iterations: sizes.count) { index in
            do {
                var simulator = try PageHistorySimulator(words: sizes[index], granularity: granularity, seed: UInt64(10_000 + index))
                let page = try simulator.run()
                let json = try JSONEncoder().encode(page.blocks())
                buffer[index] = (page.document.save().count, json.count)
            } catch {
                fatalError("Seite \(index): \(error)")
            }
        }
        let total = results.reduce(0) { $0 + $1.0 }
        let json = results.reduce(0) { $0 + $1.1 }
        let largest = results.map(\.0).max()!
        print(
            "| \(granularity.rawValue) | \(megabytes(total)) | \(format(Double(total) / Double(sizes.count) / 1024)) KB | \(format(Double(largest) / 1024)) KB | \(megabytes(json)) | \(format(Double(total) / Double(json), 2)) | \(format(milliseconds(clock.now - start) / 1000)) s |"
        )
    }
    print()
}
#endif
