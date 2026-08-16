import Foundation

public enum SecretSource: Equatable, Sendable {
    case standardInput
    case protectedFile(String)
}

public struct RecoveryOptions: Equatable, Sendable {
    public var wordlist: String?
    public var characterSet: String
    public var minimumLength: Int
    public var maximumLength: Int
    public var showPassword: Bool

    public init(wordlist: String? = nil, characterSet: String = "abcdefghijklmnopqrstuvwxyz0123456789", minimumLength: Int = 1, maximumLength: Int = 6, showPassword: Bool = false) {
        self.wordlist = wordlist
        self.characterSet=characterSet; self.minimumLength=minimumLength; self.maximumLength=maximumLength; self.showPassword=showPassword
    }
}

public enum RescueCommand: Equatable, Sendable {
    case inspect(input: String)
    case recover(input: String, options: RecoveryOptions)
    case recoverHash(input: SecretSource, options: RecoveryOptions)
    case decrypt(input: String, password: SecretSource, output: String, overwrite: Bool)
    case help
}

public enum CLIError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingValue(String)
    case duplicateOption(String)
    case unknownOption(String)
    case secretOnCommandLine
    case invalidArguments(String)

    public var description: String {
        switch self {
        case .missingCommand: "No command supplied."
        case .unknownCommand(let value): "Unknown command: \(value)"
        case .missingValue(let option): "Missing value for \(option)."
        case .duplicateOption(let option): "Duplicate option: \(option)."
        case .unknownOption(let option): "Unknown option: \(option)."
        case .secretOnCommandLine: "Secrets must be supplied through standard input or a protected file."
        case .invalidArguments(let message): message
        }
    }
}

public enum CommandRouter {
    public static func parse(_ arguments: [String]) throws -> RescueCommand {
        guard !arguments.isEmpty else { throw CLIError.missingCommand }
        if arguments.contains("--password") || arguments.contains("--hash") {
            throw CLIError.secretOnCommandLine
        }

        switch arguments[0] {
        case "help", "--help", "-h":
            guard arguments.count == 1 else { throw CLIError.invalidArguments("Help takes no options.") }
            return .help
        case "inspect":
            guard arguments.count == 2 else { throw CLIError.invalidArguments("Usage: xlsx-rescue inspect <input.xlsx>") }
            return .inspect(input: arguments[1])
        case "recover":
            guard arguments.count >= 2 else { throw CLIError.invalidArguments("Usage: xlsx-rescue recover <input.xlsx> [options]") }
            return .recover(input: arguments[1], options: try parseRecoveryOptions(Array(arguments.dropFirst(2))))
        case "recover-hash":
            return try parseRecoverHash(Array(arguments.dropFirst()))
        case "decrypt":
            return try parseDecrypt(Array(arguments.dropFirst()))
        default:
            throw CLIError.unknownCommand(arguments[0])
        }
    }

    private static func parseRecoverHash(_ arguments: [String]) throws -> RescueCommand {
        var source: SecretSource?
        var remaining: [String] = []
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--hash-stdin":
                guard source == nil else { throw CLIError.duplicateOption("--hash-stdin/--hash-file") }
                source = .standardInput
            case "--hash-file":
                guard source == nil else { throw CLIError.duplicateOption("--hash-stdin/--hash-file") }
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue("--hash-file") }
                source = .protectedFile(arguments[index])
            default:
                remaining.append(arguments[index])
            }
            index += 1
        }
        guard let source else { throw CLIError.invalidArguments("recover-hash requires --hash-stdin or --hash-file.") }
        return .recoverHash(input: source, options: try parseRecoveryOptions(remaining))
    }

    private static func parseDecrypt(_ arguments: [String]) throws -> RescueCommand {
        guard let input = arguments.first, !input.hasPrefix("-") else {
            throw CLIError.invalidArguments("decrypt requires an input workbook.")
        }
        var password: SecretSource?
        var output: String?
        var overwrite = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--password-stdin":
                guard password == nil else { throw CLIError.duplicateOption("--password-stdin/--password-file") }
                password = .standardInput
            case "--password-file":
                guard password == nil else { throw CLIError.duplicateOption("--password-stdin/--password-file") }
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue("--password-file") }
                password = .protectedFile(arguments[index])
            case "--output":
                guard output == nil else { throw CLIError.duplicateOption("--output") }
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue("--output") }
                output = arguments[index]
            case "--overwrite":
                guard !overwrite else { throw CLIError.duplicateOption("--overwrite") }
                overwrite = true
            default:
                throw CLIError.unknownOption(arguments[index])
            }
            index += 1
        }
        guard let password, let output else {
            throw CLIError.invalidArguments("decrypt requires a password source and --output.")
        }
        return .decrypt(input: input, password: password, output: output, overwrite: overwrite)
    }

    private static func parseRecoveryOptions(_ arguments: [String]) throws -> RecoveryOptions {
        var wordlist: String?
        var charset="abcdefghijklmnopqrstuvwxyz0123456789", minimum=1, maximum=6, show=false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--wordlist":
                guard wordlist == nil else { throw CLIError.duplicateOption("--wordlist") }
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue("--wordlist") }
                wordlist = arguments[index]
            case "--charset":
                index += 1; guard index < arguments.count, !arguments[index].isEmpty else { throw CLIError.missingValue("--charset") }; charset=arguments[index]
            case "--min-length":
                index += 1; guard index < arguments.count, let value=Int(arguments[index]) else { throw CLIError.missingValue("--min-length") }; minimum=value
            case "--max-length":
                index += 1; guard index < arguments.count, let value=Int(arguments[index]) else { throw CLIError.missingValue("--max-length") }; maximum=value
            case "--show-password": show=true
            default:
                throw CLIError.unknownOption(arguments[index])
            }
            index += 1
        }
        guard minimum>0,maximum>=minimum,maximum<=32 else { throw CLIError.invalidArguments("Lengths must satisfy 1 <= min <= max <= 32.") }
        return RecoveryOptions(wordlist: wordlist,characterSet:charset,minimumLength:minimum,maximumLength:maximum,showPassword:show)
    }
}
