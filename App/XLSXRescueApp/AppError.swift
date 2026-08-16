import Foundation

struct AppError: Error, Equatable, Sendable {
    let title: String
    let message: String

    static func redacted(_ error: Error, title: String = "Recovery failed") -> Self {
        if let appError = error as? AppError { return appError }
        if error is CancellationError {
            return Self(title: "Operation cancelled", message: "The operation stopped without changing the source file.")
        }
        return Self(
            title: title,
            message: "The operation could not be completed. Check the selected files and recovery settings, then try again."
        )
    }
}
