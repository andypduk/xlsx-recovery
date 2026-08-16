import Foundation

public enum OfficeHashParser {
    public static func parse(_ text: String) throws -> Office2013Parameters {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            throw OfficeHashError.unsupportedFormat
        }
        let fields = trimmed.split(separator: "*", omittingEmptySubsequences: false)
        guard fields.count == 8, fields[0] == "$office$" else {
            throw OfficeHashError.unsupportedFormat
        }

        let version = try parseDecimal(fields[1], field: "version")
        let spinCount = try parseDecimal(fields[2], field: "spin count")
        let keyBits = try parseDecimal(fields[3], field: "key bits")
        let declaredSaltBytes = try parseDecimal(fields[4], field: "salt length")
        guard declaredSaltBytes == 16 else { throw OfficeHashError.invalidLength(field: "salt") }

        let salt = try decodeHex(fields[5], expectedBytes: declaredSaltBytes, field: "salt")
        let verifier = try decodeHex(fields[6], expectedBytes: 16, field: "encrypted verifier")
        let verifierHash = try decodeHex(fields[7], expectedBytes: 32, field: "encrypted verifier hash")

        return try Office2013Parameters(
            version: version,
            spinCount: spinCount,
            keyBits: keyBits,
            salt: salt,
            encryptedVerifier: verifier,
            encryptedVerifierHash: verifierHash
        )
    }

    private static func parseDecimal(_ value: Substring, field: String) throws -> Int {
        guard !value.isEmpty,
              value.allSatisfy({ $0.isNumber && $0.isASCII }),
              let result = Int(value) else {
            throw OfficeHashError.invalidNumber(field: field)
        }
        return result
    }

    private static func decodeHex(
        _ value: Substring,
        expectedBytes: Int,
        field: String
    ) throws -> Data {
        guard value.utf8.count == expectedBytes * 2 else {
            throw OfficeHashError.invalidLength(field: field)
        }
        var result = Data(capacity: expectedBytes)
        var index = value.startIndex
        for _ in 0..<expectedBytes {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw OfficeHashError.invalidHex(field: field)
            }
            result.append(byte)
            index = next
        }
        return result
    }
}
