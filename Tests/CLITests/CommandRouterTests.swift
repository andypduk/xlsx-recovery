@testable import XLSXRescueCLI
import XCTest

final class CommandRouterTests: XCTestCase {
    func testRecoverHashRequiresStdinOrProtectedFile() {
        XCTAssertThrowsError(try CommandRouter.parse([
            "recover-hash", "--hash", "$office$*2013*100000",
        ])) { error in
            XCTAssertEqual(error as? CLIError, .secretOnCommandLine)
        }
    }

    func testDecryptRejectsPasswordArgument() {
        XCTAssertThrowsError(try CommandRouter.parse([
            "decrypt", "book.xlsx", "--password", "secret", "--output", "copy.xlsx",
        ])) { error in
            XCTAssertEqual(error as? CLIError, .secretOnCommandLine)
        }
    }

    func testRecoverHashFromStdinParses() throws {
        XCTAssertEqual(
            try CommandRouter.parse(["recover-hash", "--hash-stdin", "--wordlist", "words.txt"]),
            .recoverHash(input: .standardInput, options: .init(wordlist: "words.txt"))
        )
    }

    func testDecryptParsesProtectedSources() throws {
        XCTAssertEqual(
            try CommandRouter.parse([
                "decrypt", "book.xlsx", "--password-file", "secret.txt", "--output", "copy.xlsx",
            ]),
            .decrypt(input: "book.xlsx", password: .protectedFile("secret.txt"), output: "copy.xlsx", overwrite: false)
        )
    }

    func testDuplicateWordlistIsRejected() {
        XCTAssertThrowsError(try CommandRouter.parse([
            "recover-hash", "--hash-stdin", "--wordlist", "a", "--wordlist", "b",
        ]))
    }
}
