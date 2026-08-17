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

public struct AnyCandidateSource: CandidateSource {
    private final class Box: @unchecked Sendable {
        var stage: () -> String
        var position: () -> UInt64
        var next: (Int) throws -> CandidateBatch?
        init<S:CandidateSource>(_ value:S) {
            var source=value
            stage={source.stageID}; position={source.cursor}; next={try source.nextBatch(limit:$0)}
        }
    }
    private let box:Box
    public init<S:CandidateSource>(_ source:S){box=Box(source)}
    public var stageID:String{box.stage()}; public var cursor:UInt64{box.position()}
    public mutating func nextBatch(limit:Int)throws->CandidateBatch?{try box.next(limit)}
}

public enum CandidateSourceError: Error, Equatable {
    case emptyCharacterSet
    case emptyMask
    case searchSpaceOverflow
    case invalidBatchSize
    case invalidUTF8(offset: UInt64)
    case candidateTooLong(offset: UInt64, maximumBytes: Int)
    case cursorOutOfRange
}
