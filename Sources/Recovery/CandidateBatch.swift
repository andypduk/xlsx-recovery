import Foundation

public struct CandidateBatch: Equatable, Sendable {
    public let startCursor: UInt64
    public let candidates: [String]

    public init(startCursor: UInt64, candidates: [String]) {
        self.startCursor = startCursor
        self.candidates = candidates
    }
}

public protocol CandidateSource: Sendable {
    var stageID: String { get }
    var cursor: UInt64 { get }
    mutating func nextBatch(limit: Int) throws -> CandidateBatch?
}

public enum CandidateSourceError: Error, Equatable {
    case emptyCharacterSet
    case emptyMask
    case searchSpaceOverflow
    case invalidBatchSize
    case invalidUTF8(offset: UInt64)
    case cursorOutOfRange
}
