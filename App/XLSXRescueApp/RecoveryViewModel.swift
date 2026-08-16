import Foundation
import Observation

@MainActor
@Observable
final class RecoveryViewModel {
    var state: RecoverySessionState = .idle
    var configuration = RecoveryConfiguration()
    var hashText = ""
    var passwordRevealed = false
}
