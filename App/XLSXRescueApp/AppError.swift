import Foundation

struct AppError: Error, Equatable, Sendable {
    let title: String
    let message: String

    static func redacted(_ error: Error, title: String = "Recovery failed") -> Self {
        Self(title: title, message: String(describing: error))
    }
}
