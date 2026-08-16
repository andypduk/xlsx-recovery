import Foundation

public struct MaskCandidateSource: CandidateSource {
    public let stageID: String
    public private(set) var cursor: UInt64
    public let searchSpace: UInt64
    private let characterSets: [[Character]]

    public init(
        stageID: String = "mask-1",
        characterSets: [[Character]],
        cursor: UInt64 = 0
    ) throws {
        guard !characterSets.isEmpty else { throw CandidateSourceError.emptyMask }
        guard characterSets.allSatisfy({ !$0.isEmpty }) else { throw CandidateSourceError.emptyCharacterSet }
        var size: UInt64 = 1
        for characters in characterSets {
            let (product, overflow) = size.multipliedReportingOverflow(by: UInt64(characters.count))
            guard !overflow else { throw CandidateSourceError.searchSpaceOverflow }
            size = product
        }
        guard cursor <= size else { throw CandidateSourceError.cursorOutOfRange }
        self.stageID = stageID
        self.characterSets = characterSets
        self.cursor = cursor
        self.searchSpace = size
    }

    public mutating func nextBatch(limit: Int) throws -> CandidateBatch? {
        guard limit > 0 else { throw CandidateSourceError.invalidBatchSize }
        guard cursor < searchSpace else { return nil }
        let start = cursor
        let count = min(UInt64(limit), searchSpace - cursor)
        var candidates: [String] = []
        candidates.reserveCapacity(Int(count))
        for value in cursor..<(cursor + count) {
            candidates.append(candidate(at: value))
        }
        cursor += count
        return CandidateBatch(startCursor: start, candidates: candidates)
    }

    private func candidate(at cursor: UInt64) -> String {
        var value = cursor
        var output = Array(repeating: Character(" "), count: characterSets.count)
        for position in characterSets.indices.reversed() {
            let characters = characterSets[position]
            output[position] = characters[Int(value % UInt64(characters.count))]
            value /= UInt64(characters.count)
        }
        return String(output)
    }
}

public struct WordlistCandidateSource: CandidateSource {
    public let stageID: String
    public private(set) var cursor: UInt64
    private let data: Data

    public init(stageID: String = "wordlist-1", url: URL, cursor: UInt64 = 0) throws {
        self.stageID = stageID
        self.data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard cursor <= UInt64(data.count) else { throw CandidateSourceError.cursorOutOfRange }
        self.cursor = cursor
    }

    public mutating func nextBatch(limit: Int) throws -> CandidateBatch? {
        guard limit > 0 else { throw CandidateSourceError.invalidBatchSize }
        guard cursor < UInt64(data.count) else { return nil }
        let start = cursor
        var candidates: [String] = []
        while cursor < UInt64(data.count), candidates.count < limit {
            let lineStart = Int(cursor)
            var lineEnd = lineStart
            while lineEnd < data.count, data[lineEnd] != 0x0A, data[lineEnd] != 0x0D {
                lineEnd += 1
            }
            let line = data[lineStart..<lineEnd]
            guard let candidate = String(data: line, encoding: .utf8) else {
                throw CandidateSourceError.invalidUTF8(offset: cursor)
            }
            candidates.append(candidate)
            while lineEnd < data.count, data[lineEnd] == 0x0A || data[lineEnd] == 0x0D {
                lineEnd += 1
            }
            cursor = UInt64(lineEnd)
        }
        return CandidateBatch(startCursor: start, candidates: candidates)
    }
}

public struct MutationCandidateSource: CandidateSource {
    public let stageID: String
    public private(set) var cursor: UInt64
    private let baseWords: [String]
    private let rules: [@Sendable (String) -> String]

    public init(stageID: String = "mutations-1", baseWords: [String], cursor: UInt64 = 0) throws {
        self.stageID = stageID
        self.baseWords = baseWords
        self.rules = [
            { $0 },
            { $0.lowercased() },
            { $0.uppercased() },
            { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() },
            { $0 + "1" },
            { $0 + "!" },
            { $0 + "2024" },
            { $0 + "2025" },
            { $0 + "2026" },
        ]
        let total = UInt64(baseWords.count) * UInt64(rules.count)
        guard cursor <= total else { throw CandidateSourceError.cursorOutOfRange }
        self.cursor = cursor
    }

    public mutating func nextBatch(limit: Int) throws -> CandidateBatch? {
        guard limit > 0 else { throw CandidateSourceError.invalidBatchSize }
        let total = UInt64(baseWords.count) * UInt64(rules.count)
        guard cursor < total else { return nil }
        let start = cursor
        var output: [String] = []
        while cursor < total, output.count < limit {
            let wordIndex = Int(cursor / UInt64(rules.count))
            let ruleIndex = Int(cursor % UInt64(rules.count))
            output.append(rules[ruleIndex](baseWords[wordIndex]))
            cursor += 1
        }
        return CandidateBatch(startCursor: start, candidates: output)
    }
}
