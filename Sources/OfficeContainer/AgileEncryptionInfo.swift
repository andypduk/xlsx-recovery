import Foundation
import OfficeCrypto

public enum AgileEncryptionError: Error, Equatable {
    case invalidHeader
    case invalidXML
    case missingField(String)
    case unsupported(String)
    case invalidValue(String)
}

public struct AgileEncryptionDescriptor: Sendable {
    public let keyDataSalt: Data
    public let passwordSalt: Data
    public let spinCount: Int
    public let encryptedVerifier: Data
    public let encryptedVerifierHash: Data
    public let encryptedKeyValue: Data

    public var passwordParameters: Office2013Parameters {
        get throws {
            try Office2013Parameters(version: 2013, spinCount: spinCount, keyBits: 256,
                salt: passwordSalt, encryptedVerifier: encryptedVerifier,
                encryptedVerifierHash: encryptedVerifierHash.prefix(32))
        }
    }
}

public enum AgileEncryptionInfo {
    public static func parse(_ stream: Data) throws -> AgileEncryptionDescriptor {
        guard stream.count > 8, stream.u16LE(0) == 4, stream.u16LE(2) == 4 else {
            throw AgileEncryptionError.invalidHeader
        }
        let delegate = AgileXMLDelegate()
        let parser = XMLParser(data: stream.dropFirst(8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil else { throw delegate.failure ?? .invalidXML }
        return try delegate.descriptor()
    }
}

private final class AgileXMLDelegate: NSObject, XMLParserDelegate {
    var keyData: [String:String]?
    var encryptedKey: [String:String]?
    var failure: AgileEncryptionError?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "keyData" { keyData = attributeDict }
        if name == "encryptedKey" { encryptedKey = attributeDict }
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failure = .invalidXML
        return nil
    }

    func descriptor() throws -> AgileEncryptionDescriptor {
        guard let kd = keyData else { throw AgileEncryptionError.missingField("keyData") }
        guard let ek = encryptedKey else { throw AgileEncryptionError.missingField("encryptedKey") }
        try require(kd, "cipherAlgorithm", equals: "AES")
        try require(kd, "cipherChaining", contains: "ChainingModeCBC")
        try require(kd, "hashAlgorithm", equals: "SHA512")
        try require(kd, "keyBits", equals: "256")
        try require(kd, "blockSize", equals: "16")
        try require(ek, "cipherAlgorithm", equals: "AES")
        try require(ek, "hashAlgorithm", equals: "SHA512")
        try require(ek, "keyBits", equals: "256")
        guard let spinText = ek["spinCount"], let spin = Int(spinText), spin == 100_000 else {
            throw AgileEncryptionError.unsupported("spinCount")
        }
        return try .init(
            keyDataSalt: decode(kd, "saltValue", exact: 16),
            passwordSalt: decode(ek, "saltValue", exact: 16),
            spinCount: spin,
            encryptedVerifier: decode(ek, "encryptedVerifierHashInput", exact: 16),
            encryptedVerifierHash: decode(ek, "encryptedVerifierHashValue", minimum: 32),
            encryptedKeyValue: decode(ek, "encryptedKeyValue", minimum: 32)
        )
    }

    private func require(_ values:[String:String], _ key:String, equals:String) throws {
        guard values[key] == equals else { throw AgileEncryptionError.unsupported(key) }
    }
    private func require(_ values:[String:String], _ key:String, contains:String) throws {
        guard values[key]?.contains(contains) == true else { throw AgileEncryptionError.unsupported(key) }
    }
    private func decode(_ values:[String:String], _ key:String, exact:Int? = nil, minimum:Int? = nil) throws -> Data {
        guard let text=values[key], let data=Data(base64Encoded:text) else { throw AgileEncryptionError.missingField(key) }
        if let exact, data.count != exact { throw AgileEncryptionError.invalidValue(key) }
        if let minimum, data.count < minimum || !data.count.isMultiple(of:16) { throw AgileEncryptionError.invalidValue(key) }
        return data
    }
}

private extension Data {
    func u16LE(_ offset:Int)->UInt16 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset:offset,as:UInt16.self).littleEndian } }
}
