import Foundation

enum RecoveryInput: Equatable, Sendable {
    case workbook(URL)
    case officeHash(String)
}

struct InputSummary: Equatable, Sendable {
    let title: String
    let detail: String
    let input: RecoveryInput
}

struct CheckpointSummary: Equatable, Sendable {
    let tested: UInt64
    let checkpointURL: URL?
}

struct RecoveryResultSummary: Equatable, Sendable {
    let password: String
    let sourceWorkbook: URL?
}

enum RecoverySessionState: Equatable, Sendable {
    case idle
    case inspecting
    case ready(InputSummary)
    case recovering(ProgressPresentation)
    case paused(CheckpointSummary)
    case recovered(RecoveryResultSummary)
    case decrypting
    case completed(output: URL)
    case failed(AppError)
}
