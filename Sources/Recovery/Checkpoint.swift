import CryptoKit
import Foundation

public struct RecoveryIdentity: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let configurationDigest: String

    public init(fingerprint: String, configurationDigest: String) {
        self.fingerprint = fingerprint
        self.configurationDigest = configurationDigest
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct RecoveryCheckpoint: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let identity: RecoveryIdentity
    public let stage: String
    public let cursor: UInt64
    public let tested: UInt64
    public let elapsedSeconds: TimeInterval

    public init(
        identity: RecoveryIdentity,
        stage: String,
        cursor: UInt64,
        tested: UInt64,
        elapsedSeconds: TimeInterval = 0
    ) {
        self.version = Self.currentVersion
        self.identity = identity
        self.stage = stage
        self.cursor = cursor
        self.tested = tested
        self.elapsedSeconds = elapsedSeconds
    }

    public func validate(identity expected: RecoveryIdentity) throws {
        guard version == Self.currentVersion else { throw CheckpointError.unsupportedVersion }
        guard identity == expected else { throw CheckpointError.identityMismatch }
    }

    public static func load(from url: URL, matching identity: RecoveryIdentity) throws -> Self {
        let checkpoint = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try checkpoint.validate(identity: identity)
        return checkpoint
    }

    public func saveAtomically(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let data = try JSONEncoder.sorted.encode(self)
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch CocoaError.fileNoSuchFile {
            try handle.close()
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

public enum CheckpointError: Error, Equatable {
    case unsupportedVersion
    case identityMismatch
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
