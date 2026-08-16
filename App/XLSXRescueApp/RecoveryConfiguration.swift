import Foundation

enum RecoveryMethod: Equatable, Sendable {
    case wordlist(URL)
    case bruteForce(characterSet: String, minimumLength: Int, maximumLength: Int)
}

struct RecoveryConfiguration: Equatable, Sendable {
    var method: RecoveryMethod = .bruteForce(
        characterSet: "abcdefghijklmnopqrstuvwxyz0123456789",
        minimumLength: 1,
        maximumLength: 6
    )

    func validate(fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) throws {
        switch method {
        case .wordlist(let url):
            guard fileExists(url) else { throw ConfigurationError.wordlistUnavailable }
        case .bruteForce(let characterSet, let minimum, let maximum):
            guard !characterSet.isEmpty else { throw ConfigurationError.emptyCharacterSet }
            guard minimum > 0, maximum >= minimum, maximum <= 32 else { throw ConfigurationError.invalidLengthRange }
            _ = try totalCandidates
        }
    }

    var totalCandidates: UInt64? {
        get throws {
            guard case .bruteForce(let characters, let minimum, let maximum) = method else { return nil }
            let radix = UInt64(Set(characters).count)
            guard radix > 0 else { throw ConfigurationError.emptyCharacterSet }
            var power: UInt64 = 1
            var total: UInt64 = 0
            for length in 1...maximum {
                let (nextPower, overflow) = power.multipliedReportingOverflow(by: radix)
                guard !overflow else { throw ConfigurationError.searchSpaceOverflow }
                power = nextPower
                if length >= minimum {
                    let (nextTotal, sumOverflow) = total.addingReportingOverflow(power)
                    guard !sumOverflow else { throw ConfigurationError.searchSpaceOverflow }
                    total = nextTotal
                }
            }
            return total
        }
    }
}

enum ConfigurationError: Error, Equatable {
    case emptyCharacterSet
    case invalidLengthRange
    case searchSpaceOverflow
    case wordlistUnavailable
}
