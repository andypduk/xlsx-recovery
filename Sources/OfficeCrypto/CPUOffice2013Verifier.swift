import CommonCrypto
import Foundation

public enum CPUOffice2013Verifier {
    public static func verify(
        candidate: String,
        against parameters: Office2013Parameters
    ) throws -> Bool {
        let keys = try Office2013KDF.derive(password: candidate, parameters: parameters)
        let verifier = try decryptCBC(
            parameters.encryptedVerifier,
            key: keys.verifierInputKey,
            iv: parameters.salt
        )
        let expectedHash = Office2013KDF.sha512(verifier).prefix(parameters.encryptedVerifierHash.count)
        let actualHash = try decryptCBC(
            parameters.encryptedVerifierHash,
            key: keys.verifierHashKey,
            iv: parameters.salt
        )
        return constantTimeEqual(Data(expectedHash), actualHash)
    }

    private static func decryptCBC(_ input: Data, key: Data, iv: Data) throws -> Data {
        precondition(input.count.isMultiple(of: kCCBlockSizeAES128))
        var output = Data(count: input.count)
        let outputCount = output.count
        var bytesWritten = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCount,
                            &bytesWritten
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, bytesWritten == input.count else {
            throw OfficeCryptoError.cipherFailure(status)
        }
        return output
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
