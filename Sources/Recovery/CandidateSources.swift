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
    private static let readChunkSize = 64 * 1_024
    private static let maximumCandidateBytes = 4_096

    public let stageID: String
    public private(set) var cursor: UInt64
    private let handle: FileHandle
    private var buffer = Data()
    private var bufferIndex = 0
    private var reachedEnd = false

    public init(stageID: String = "wordlist-1", url: URL, cursor: UInt64 = 0) throws {
        self.stageID = stageID
        let handle = try FileHandle(forReadingFrom: url)
        let fileSize = try handle.seekToEnd()
        guard cursor <= fileSize else {
            try? handle.close()
            throw CandidateSourceError.cursorOutOfRange
        }
        try handle.seek(toOffset: cursor)
        self.handle = handle
        self.cursor = cursor
    }

    public mutating func nextBatch(limit: Int) throws -> CandidateBatch? {
        guard limit > 0 else { throw CandidateSourceError.invalidBatchSize }
        let start = cursor
        var candidates: [String] = []
        candidates.reserveCapacity(limit)
        while candidates.count < limit, let candidate = try nextCandidate() {
            candidates.append(candidate)
        }
        guard !candidates.isEmpty else { return nil }
        return CandidateBatch(startCursor: start, candidates: candidates)
    }

    private mutating func nextCandidate() throws -> String? {
        let candidateOffset = cursor
        while true {
            if let delimiter = buffer[bufferIndex...].firstIndex(where: Self.isLineDelimiter) {
                let byteCount = delimiter - bufferIndex
                try validateCandidateLength(byteCount, offset: candidateOffset)
                guard let candidate = String(data: buffer[bufferIndex..<delimiter], encoding: .utf8) else {
                    throw CandidateSourceError.invalidUTF8(offset: candidateOffset)
                }
                bufferIndex = delimiter
                cursor += UInt64(byteCount)
                try skipLineDelimiters()
                return candidate
            }

            let byteCount = buffer.count - bufferIndex
            try validateCandidateLength(byteCount, offset: candidateOffset)
            if reachedEnd {
                guard byteCount > 0 else { return nil }
                guard let candidate = String(data: buffer[bufferIndex...], encoding: .utf8) else {
                    throw CandidateSourceError.invalidUTF8(offset: candidateOffset)
                }
                bufferIndex = buffer.count
                cursor += UInt64(byteCount)
                return candidate
            }
            try readMore()
        }
    }

    private mutating func skipLineDelimiters() throws {
        while true {
            while bufferIndex < buffer.count, Self.isLineDelimiter(buffer[bufferIndex]) {
                bufferIndex += 1
                cursor += 1
            }
            guard bufferIndex == buffer.count, !reachedEnd else { return }
            try readMore()
        }
    }

    private mutating func readMore() throws {
        if bufferIndex > 0 {
            buffer.removeSubrange(buffer.startIndex..<bufferIndex)
            bufferIndex = 0
        }
        let chunk = try handle.read(upToCount: Self.readChunkSize) ?? Data()
        if chunk.isEmpty {
            reachedEnd = true
        } else {
            buffer.append(chunk)
        }
    }

    private func validateCandidateLength(_ byteCount: Int, offset: UInt64) throws {
        guard byteCount <= Self.maximumCandidateBytes else {
            throw CandidateSourceError.candidateTooLong(
                offset: offset,
                maximumBytes: Self.maximumCandidateBytes
            )
        }
    }

    private static func isLineDelimiter(_ byte: UInt8) -> Bool {
        byte == 0x0A || byte == 0x0D
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
