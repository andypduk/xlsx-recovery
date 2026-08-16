import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardService {
    private(set) var lastCopiedAt: Date?

    func copy(_ password: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        lastCopiedAt = Date()
    }
}
