import Foundation

private let help = """
    xlsx-rescue inspect <input.xlsx>
    xlsx-rescue recover <input.xlsx> [--wordlist <path>]
    xlsx-rescue recover-hash (--hash-stdin | --hash-file <path>) [--wordlist <path>]
    xlsx-rescue decrypt <input.xlsx> (--password-stdin | --password-file <path>) --output <copy.xlsx>
    """

do {
    let command = try CommandRouter.parse(Array(CommandLine.arguments.dropFirst()))
    switch command {
    case .help:
        print(help)
    default:
        fputs("This command is not implemented yet.\n", stderr)
        Foundation.exit(2)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    Foundation.exit(2)
}
