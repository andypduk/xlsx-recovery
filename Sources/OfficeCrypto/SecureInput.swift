import Darwin
import Foundation

public enum SecureInputError: Error, Equatable {
    case noInput
    case invalidUTF8
    case insecurePermissions(path: String, mode: UInt16)
    case notRegularFile(path: String)
}

public enum SecureInput {
    public static func readSecret(prompt: String, inputFD: Int32 = STDIN_FILENO) throws -> [UInt8] {
        if isatty(inputFD) != 0 {
            FileHandle.standardError.write(Data(prompt.utf8))
            var original = termios()
            guard tcgetattr(inputFD, &original) == 0 else { throw POSIXError(.EIO) }
            var hidden = original
            hidden.c_lflag &= ~tcflag_t(ECHO)
            guard tcsetattr(inputFD, TCSAFLUSH, &hidden) == 0 else { throw POSIXError(.EIO) }
            defer {
                var restored = original
                _ = tcsetattr(inputFD, TCSAFLUSH, &restored)
                FileHandle.standardError.write(Data("\n".utf8))
            }
            return try readBytes(from: inputFD)
        }
        return try readBytes(from: inputFD)
    }

    private static func readBytes(from inputFD: Int32) throws -> [UInt8] {
        guard let data = try FileHandle(fileDescriptor: inputFD, closeOnDealloc: false).readToEnd(),
              !data.isEmpty else {
            throw SecureInputError.noInput
        }
        return trimLineEnding(Array(data))
    }

    public static func readVerifier(
        from source: URL,
        allowInsecurePermissions: Bool = false
    ) throws -> String {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw SecureInputError.notRegularFile(path: source.path)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        if !allowInsecurePermissions, mode & 0o077 != 0 {
            throw SecureInputError.insecurePermissions(path: source.path, mode: mode)
        }

        let bytes = try Data(contentsOf: source, options: [.mappedIfSafe])
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw SecureInputError.invalidUTF8
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimLineEnding(_ bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        while result.last == 0x0A || result.last == 0x0D {
            result.removeLast()
        }
        return result
    }
}
