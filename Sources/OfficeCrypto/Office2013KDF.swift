import CryptoKit
import Foundation

public struct Office2013DerivedKeys: Sendable {
    public let verifierInputKey: Data
    public let verifierHashKey: Data
}

public enum OfficeCryptoError: Error, Equatable {
    case invalidCandidate
    case cipherFailure(Int32)
}

public enum Office2013KDF {
    public static let verifierInputBlockKey = Data([0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79])
    public static let verifierHashBlockKey = Data([0xD7, 0xAA, 0x0F, 0x6D, 0x30, 0x61, 0x34, 0x4E])

    public static func passwordBytes(_ password: String) -> Data {
        var bytes = Data(capacity: password.utf16.count * 2)
        for codeUnit in password.utf16 {
            bytes.append(UInt8(truncatingIfNeeded: codeUnit))
            bytes.append(UInt8(truncatingIfNeeded: codeUnit >> 8))
        }
        return bytes
    }

    public static func derive(
        password: String,
        parameters: Office2013Parameters
    ) throws -> Office2013DerivedKeys {
        guard !password.utf8.contains(0) else { throw OfficeCryptoError.invalidCandidate }

        let digest = try spinDigest(password: password, parameters: parameters)
        return deriveKeys(spinDigest: digest)
    }

    public static func spinDigest(
        password: String,
        parameters: Office2013Parameters
    ) throws -> Data {
        guard !password.utf8.contains(0) else { throw OfficeCryptoError.invalidCandidate }
        var initial = Data(capacity: parameters.salt.count + password.utf16.count * 2)
        initial.append(parameters.salt)
        initial.append(passwordBytes(password))
        var digest = sha512(initial)

        var iterationInput = Data(count: 4 + SHA512.byteCount)
        for iteration in 0..<parameters.spinCount {
            digest.withUnsafeBytes { digestBytes in
                iterationInput.withUnsafeMutableBytes { raw in
                    let value=UInt32(iteration).littleEndian
                    raw[0]=UInt8(truncatingIfNeeded:value); raw[1]=UInt8(truncatingIfNeeded:value>>8)
                    raw[2]=UInt8(truncatingIfNeeded:value>>16); raw[3]=UInt8(truncatingIfNeeded:value>>24)
                    raw.baseAddress!.advanced(by: 4).copyMemory(from:digestBytes.baseAddress!,byteCount:digestBytes.count)
                }
            }
            digest = sha512(iterationInput)
        }
        return digest
    }

    public static func deriveKeys(spinDigest digest: Data) -> Office2013DerivedKeys {
        precondition(digest.count == SHA512.byteCount)
        return Office2013DerivedKeys(
            verifierInputKey: deriveKey(digest: digest, blockKey: verifierInputBlockKey),
            verifierHashKey: deriveKey(digest: digest, blockKey: verifierHashBlockKey)
        )
    }

    public static func deriveKey(spinDigest digest: Data, blockKey: Data, keyBytes: Int = 32) -> Data {
        precondition(digest.count == SHA512.byteCount && keyBytes > 0 && keyBytes <= SHA512.byteCount)
        var input=Data(); input.append(digest); input.append(blockKey)
        return sha512(input).prefix(keyBytes)
    }

    public static func sha512(_ data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }

    private static func deriveKey(digest: Data, blockKey: Data) -> Data {
        var input = Data(capacity: digest.count + blockKey.count)
        input.append(digest)
        input.append(blockKey)
        return sha512(input).prefix(32)
    }
}
