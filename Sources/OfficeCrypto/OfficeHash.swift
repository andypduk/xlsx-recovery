import Foundation

public struct Office2013Parameters: Hashable, Sendable {
    public let version: Int
    public let spinCount: Int
    public let keyBits: Int
    public let salt: Data
    public let encryptedVerifier: Data
    public let encryptedVerifierHash: Data

    public init(
        version: Int,
        spinCount: Int,
        keyBits: Int,
        salt: Data,
        encryptedVerifier: Data,
        encryptedVerifierHash: Data
    ) throws {
        guard version == 2013 else { throw OfficeHashError.unsupportedVersion(version) }
        guard (1...10_000_000).contains(spinCount) else { throw OfficeHashError.invalidSpinCount }
        guard keyBits == 256 else { throw OfficeHashError.unsupportedKeyBits(keyBits) }
        guard salt.count == 16 else { throw OfficeHashError.invalidLength(field: "salt") }
        guard encryptedVerifier.count == 16 else { throw OfficeHashError.invalidLength(field: "encrypted verifier") }
        guard encryptedVerifierHash.count == 32 else { throw OfficeHashError.invalidLength(field: "encrypted verifier hash") }

        self.version = version
        self.spinCount = spinCount
        self.keyBits = keyBits
        self.salt = salt
        self.encryptedVerifier = encryptedVerifier
        self.encryptedVerifierHash = encryptedVerifierHash
    }
}

public enum OfficeHashError: Error, Equatable, CustomStringConvertible {
    case unsupportedFormat
    case unsupportedVersion(Int)
    case invalidNumber(field: String)
    case invalidSpinCount
    case unsupportedKeyBits(Int)
    case invalidHex(field: String)
    case invalidLength(field: String)

    public var description: String {
        switch self {
        case .unsupportedFormat: "Unsupported Office verifier format."
        case .unsupportedVersion(let version): "Unsupported Office version: \(version)."
        case .invalidNumber(let field): "Invalid numeric field: \(field)."
        case .invalidSpinCount: "Spin count is outside the supported range."
        case .unsupportedKeyBits(let bits): "Unsupported key size: \(bits) bits."
        case .invalidHex(let field): "Invalid hexadecimal data in \(field)."
        case .invalidLength(let field): "Invalid byte length for \(field)."
        }
    }
}
