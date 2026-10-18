import Testing
@testable import QuillModel

@Suite struct FractionalIndexTests {
    @Test func firstKeyIsMiddle() throws {
        #expect(try FractionalIndex.key(between: nil, and: nil) == "V")
        #expect(try FractionalIndex.key(between: "", and: "") == "V")
    }

    @Test func keysAreStrictlyBetween() throws {
        let cases: [(String?, String?)] = [
            (nil, "V"), ("V", nil), ("V", "W"), ("V", "X"), ("V", "VX"),
            ("V0X", "V1"), (nil, "1"), (nil, "01"), ("z", nil), ("zz", nil), ("y", "z"),
            ("Vz", "W"), ("a", "a1"),
        ]
        for (lower, upper) in cases {
            let key = try FractionalIndex.key(between: lower, and: upper)
            #expect(FractionalIndex.isValid(key), "\(key)")
            if let lower { #expect(lower < key, "\(lower) < \(key)") }
            if let upper { #expect(key < upper, "\(key) < \(upper)") }
        }
    }

    @Test func appendingStaysShort() throws {
        var last: String?
        for _ in 0..<1000 {
            let key = try FractionalIndex.key(between: last, and: nil)
            if let last { #expect(last < key) }
            last = key
        }
        #expect((last?.count ?? 0) <= 20)
    }

    @Test func prependingStaysShort() throws {
        var first: String?
        for _ in 0..<1000 {
            let key = try FractionalIndex.key(between: nil, and: first)
            if let first { #expect(key < first) }
            #expect(FractionalIndex.isValid(key))
            first = key
        }
        #expect((first?.count ?? 0) <= 20)
    }

    @Test func repeatedInsertAtSamePositionStaysOrdered() throws {
        let lower = "V"
        var upper = "W"
        for _ in 0..<200 {
            let key = try FractionalIndex.key(between: lower, and: upper)
            #expect(lower < key && key < upper)
            upper = key
        }
    }

    @Test func randomInsertsKeepOrder() throws {
        var generator = SplitMix64(seed: 42)
        var keys: [String] = []
        for _ in 0..<2000 {
            let index = Int.random(in: 0...keys.count, using: &generator)
            let lower = index > 0 ? keys[index - 1] : nil
            let upper = index < keys.count ? keys[index] : nil
            let key = try FractionalIndex.key(between: lower, and: upper)
            #expect(FractionalIndex.isValid(key))
            keys.insert(key, at: index)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }

    @Test func keysForCountAreAscending() {
        let keys = FractionalIndex.keys(count: 100)
        #expect(keys.count == 100)
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == 100)
    }

    @Test func rejectsInvalidInput() {
        #expect(throws: FractionalIndex.Error.invalidKey("V0")) {
            try FractionalIndex.key(between: "V0", and: nil)
        }
        #expect(throws: FractionalIndex.Error.invalidKey("ä")) {
            try FractionalIndex.key(between: nil, and: "ä")
        }
        #expect(throws: FractionalIndex.Error.invalidOrder(lower: "W", upper: "V")) {
            try FractionalIndex.key(between: "W", and: "V")
        }
        #expect(throws: FractionalIndex.Error.invalidOrder(lower: "V", upper: "V")) {
            try FractionalIndex.key(between: "V", and: "V")
        }
        #expect(!FractionalIndex.isValid(""))
    }

    @Test func keysInGapAreAscendingAndInside() throws {
        let keys = try FractionalIndex.keys(count: 100, between: "V", and: "W")
        #expect(keys.count == 100)
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 })
        #expect(keys.allSatisfy { $0 > "V" && $0 < "W" })
        #expect(try FractionalIndex.keys(count: 0, between: nil, and: nil).isEmpty)
    }
}

/// Deterministischer Zufall für reproduzierbare Tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
