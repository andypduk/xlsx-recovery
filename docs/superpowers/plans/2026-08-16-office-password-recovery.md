# Office Password Recovery Utility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native Swift command-line utility that securely tests password candidates against Office 2013 Agile Encryption, accelerates the verified hot path with Metal on Apple Silicon, and exports a validated unencrypted copy after recovery.

**Architecture:** A Swift package separates strict input parsing, Office cryptography, deterministic candidate production, recovery orchestration, and compound-file/package export. A CommonCrypto-backed CPU verifier is the correctness oracle; a specialized Metal backend is enabled only after runtime equivalence checks and benchmarking. All source documents are opened read-only, and decrypted output is written transactionally to a distinct path.

**Tech Stack:** Swift 6.2, Swift Package Manager, Foundation, ArgumentParser-free CLI parsing, CommonCrypto, Metal/MetalKit, XCTest, macOS Tahoe 26.6.1 on Apple M4.

## Global Constraints

- Initial target: Apple M4 MacBook Air with 24 GB unified memory running macOS Tahoe 26.6.1.
- Version 1 supports modern ECMA-376 Agile Encryption and specializes Office 2013, SHA-512, 100,000 iterations, 256-bit AES, and a 16-byte salt.
- Do not add third-party runtime dependencies or bundled password lists.
- Never accept passwords or `$office$` verifier strings as ordinary command-line arguments.
- Never log candidates, verifier strings, derived keys, decrypted bytes, or recovered passwords.
- Open source workbooks read-only and never overwrite them.
- Publish decrypted output only after cryptographic and OOXML validation.
- The CPU implementation is the correctness oracle; enable Metal only after equivalence testing.
- Do not claim arbitrary strong passwords are recoverable.

## File Map

```text
Package.swift                                      Swift package, targets, linker settings, resources
Sources/XLSXRescueCLI/main.swift                    Process entry point and exit handling
Sources/XLSXRescueCLI/CommandRouter.swift           Strict command/option parsing
Sources/OfficeCrypto/OfficeHash.swift               Validated common encryption parameter model
Sources/OfficeCrypto/OfficeHashParser.swift         `$office$` verifier parser
Sources/OfficeCrypto/SecureInput.swift              stdin and permission-checked file input
Sources/OfficeCrypto/CPUOffice2013Verifier.swift    CommonCrypto SHA-512/AES verifier oracle
Sources/OfficeCrypto/Office2013KDF.swift            Office 2013 key derivation and block keys
Sources/Recovery/CandidateBatch.swift               Candidate batch representation
Sources/Recovery/CandidateSources.swift             Wordlist, mask, brute-force, mutation sources
Sources/Recovery/Checkpoint.swift                   Stable resumable cursor format
Sources/Recovery/RecoveryEngine.swift               Back-pressure, progress, cancellation, matches
Sources/MetalVerifier/MetalOffice2013Verifier.swift Metal device/pipeline/buffer orchestration
Sources/MetalVerifier/Office2013Verifier.metal       Specialized SHA-512/AES verification kernel
Sources/MetalVerifier/BackendSelector.swift          Equivalence check, calibration, fallback
Sources/OfficeContainer/CompoundFile.swift           Bounds-checked OLE CFB reader
Sources/OfficeContainer/AgileEncryptionInfo.swift    ECMA-376 Agile XML descriptor parser
Sources/OfficeContainer/EncryptedPackage.swift       Streaming package decryption
Sources/OfficeContainer/OOXMLValidator.swift         ZIP structure and required-entry validation
Tests/OfficeCryptoTests/OfficeHashParserTests.swift  Parser and secure-input tests
Tests/OfficeCryptoTests/Office2013KDFTests.swift     Known-answer KDF/verifier tests
Tests/RecoveryTests/CandidateSourcesTests.swift      Candidate order and cursor tests
Tests/RecoveryTests/CheckpointTests.swift            Checkpoint identity/resume tests
Tests/RecoveryTests/RecoveryEngineTests.swift        Recovery, cancellation, progress tests
Tests/MetalVerifierTests/MetalEquivalenceTests.swift CPU/Metal randomized equivalence tests
Tests/OfficeContainerTests/CompoundFileTests.swift   Valid/corrupt CFB fixtures
Tests/OfficeContainerTests/PackageDecryptTests.swift Decrypt/export/source-integrity tests
Tests/CLITests/CommandRouterTests.swift              CLI secrecy and validation tests
Tests/Fixtures/README.md                              Reproducible synthetic-fixture instructions
README.md                                             Usage, limits, safety, and benchmarks
```

---

### Task 1: Package Skeleton and Secret-Safe CLI

**Files:**
- Create: `Package.swift`
- Create: `Sources/XLSXRescueCLI/main.swift`
- Create: `Sources/XLSXRescueCLI/CommandRouter.swift`
- Create: `Sources/OfficeCrypto/SecureInput.swift`
- Create: `Tests/CLITests/CommandRouterTests.swift`

**Interfaces:**
- Produces: `enum RescueCommand`, `CommandRouter.parse(_:) throws -> RescueCommand`
- Produces: `SecureInput.readLine(prompt:) throws -> [UInt8]`
- Produces: `SecureInput.readVerifier(from:) throws -> String`

- [ ] **Step 1: Write failing command-routing and secret-rejection tests**

```swift
@testable import XLSXRescueCLI
import XCTest

final class CommandRouterTests: XCTestCase {
    func testRecoverHashRequiresStdinOrProtectedFile() throws {
        XCTAssertThrowsError(try CommandRouter.parse([
            "recover-hash", "--hash", "$office$*2013*100000"
        ]))
    }

    func testDecryptRejectsPasswordArgument() throws {
        XCTAssertThrowsError(try CommandRouter.parse([
            "decrypt", "book.xlsx", "--password", "secret", "--output", "copy.xlsx"
        ]))
    }

    func testRecoverHashFromStdinParses() throws {
        XCTAssertEqual(
            try CommandRouter.parse(["recover-hash", "--hash-stdin", "--wordlist", "words.txt"]),
            .recoverHash(input: .standardInput, options: .init(wordlist: "words.txt"))
        )
    }
}
```

- [ ] **Step 2: Create the Swift package and verify the tests fail for missing symbols**

Run: `swift test --filter CommandRouterTests`

Expected: compilation fails because `CommandRouter` and `RescueCommand` do not exist.

- [ ] **Step 3: Implement strict command types and parsing**

```swift
public enum SecretSource: Equatable, Sendable {
    case standardInput
    case protectedFile(String)
}

public struct RecoveryOptions: Equatable, Sendable {
    public var wordlist: String?
    public init(wordlist: String? = nil) { self.wordlist = wordlist }
}

public enum RescueCommand: Equatable, Sendable {
    case inspect(input: String)
    case recover(input: String, options: RecoveryOptions)
    case recoverHash(input: SecretSource, options: RecoveryOptions)
    case decrypt(input: String, password: SecretSource, output: String, overwrite: Bool)
}

public enum CommandRouter {
    public static func parse(_ arguments: [String]) throws -> RescueCommand {
        guard !arguments.contains("--password"), !arguments.contains("--hash") else {
            throw CLIError.secretOnCommandLine
        }
        // Parse only documented commands; reject unknown and duplicate options.
    }
}
```

Implement `SecureInput` with `read(2)`/`termios` for echo-disabled passwords and `FileManager.attributesOfItem` permission checks that reject group/world-readable verifier files unless `allowInsecurePermissions` is explicitly true. Zero mutable byte buffers with `resetBytes(in:)` after use.

- [ ] **Step 4: Run CLI tests and inspect help text for secrets**

Run: `swift test --filter CommandRouterTests`

Expected: all tests pass, and no help or error string contains an actual secret value.

- [ ] **Step 5: Commit the skeleton**

```bash
git add Package.swift Sources/XLSXRescueCLI Sources/OfficeCrypto/SecureInput.swift Tests/CLITests
git commit -m "feat: scaffold secret-safe recovery CLI"
```

### Task 2: Strict `$office$` Parser and Common Parameter Model

**Files:**
- Create: `Sources/OfficeCrypto/OfficeHash.swift`
- Create: `Sources/OfficeCrypto/OfficeHashParser.swift`
- Create: `Tests/OfficeCryptoTests/OfficeHashParserTests.swift`

**Interfaces:**
- Produces: `OfficeHashParser.parse(_:) throws -> Office2013Parameters`
- Produces: `Office2013Parameters(version:spinCount:keyBits:salt:encryptedVerifier:encryptedVerifierHash:)`

- [ ] **Step 1: Write parser tests using synthetic values**

```swift
@testable import OfficeCrypto
import XCTest

final class OfficeHashParserTests: XCTestCase {
    let valid = "$office$*2013*100000*256*16*000102030405060708090a0b0c0d0e0f*00112233445566778899aabbccddeeff*000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

    func testParsesOffice2013Verifier() throws {
        let value = try OfficeHashParser.parse(valid)
        XCTAssertEqual(value.spinCount, 100_000)
        XCTAssertEqual(value.keyBits, 256)
        XCTAssertEqual(value.salt.count, 16)
        XCTAssertEqual(value.encryptedVerifier.count, 16)
        XCTAssertEqual(value.encryptedVerifierHash.count, 32)
    }

    func testRejectsBadHexAndDeclaredLengthMismatch() {
        XCTAssertThrowsError(try OfficeHashParser.parse(valid.replacingOccurrences(of: "0001", with: "zz01")))
        XCTAssertThrowsError(try OfficeHashParser.parse(valid.replacingOccurrences(of: "*16*", with: "*15*")))
    }
}
```

- [ ] **Step 2: Run the parser tests and confirm the missing-type failure**

Run: `swift test --filter OfficeHashParserTests`

Expected: compilation fails because `OfficeHashParser` is undefined.

- [ ] **Step 3: Implement the immutable validated model and parser**

```swift
public struct Office2013Parameters: Hashable, Sendable {
    public let version: Int
    public let spinCount: Int
    public let keyBits: Int
    public let salt: [UInt8]
    public let encryptedVerifier: [UInt8]
    public let encryptedVerifierHash: [UInt8]
}

public enum OfficeHashParser {
    public static func parse(_ text: String) throws -> Office2013Parameters {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "*", omittingEmptySubsequences: false)
        guard fields.count == 9, fields[0] == "$office$", fields[1] == "2013" else {
            throw OfficeHashError.unsupportedFormat
        }
        // Parse with exact numeric bounds and exact-length hexadecimal decoding.
    }
}
```

Accept only version `2013`, spin count `1...10_000_000`, key bits `256`, salt length `16`, 16 verifier bytes, and 32 verifier-hash bytes in version 1. Reject odd-length, non-ASCII, and non-hexadecimal fields before allocation.

- [ ] **Step 4: Run parser tests plus malformed-input fuzz seeds**

Run: `swift test --filter OfficeHashParserTests`

Expected: all parser tests pass without crashes or verifier text in failures.

- [ ] **Step 5: Commit the parser**

```bash
git add Sources/OfficeCrypto/OfficeHash.swift Sources/OfficeCrypto/OfficeHashParser.swift Tests/OfficeCryptoTests
git commit -m "feat: parse Office 2013 verifier hashes"
```

### Task 3: CPU Office 2013 Verification Oracle

**Files:**
- Create: `Sources/OfficeCrypto/Office2013KDF.swift`
- Create: `Sources/OfficeCrypto/CPUOffice2013Verifier.swift`
- Create: `Tests/OfficeCryptoTests/Office2013KDFTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `Office2013Parameters`
- Produces: `Office2013KDF.derive(passwordUTF16LE:parameters:) throws -> Office2013DerivedKeys`
- Produces: `CPUOffice2013Verifier.verify(candidate:against:) throws -> Bool`

- [ ] **Step 1: Add known-answer tests generated from a disposable encrypted workbook**

```swift
func testCorrectPasswordMatchesAndWrongPasswordDoesNot() throws {
    let parameters = try OfficeHashParser.parse(Self.fixtureVerifier)
    XCTAssertTrue(try CPUOffice2013Verifier.verify(candidate: "Correct Horse", against: parameters))
    XCTAssertFalse(try CPUOffice2013Verifier.verify(candidate: "Correct horse", against: parameters))
}

func testPasswordEncodingIsUTF16LittleEndian() {
    XCTAssertEqual(Office2013KDF.passwordBytes("A😀"), [0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE])
}
```

Record the fixture-generation command and password in `Tests/Fixtures/README.md`; never use the user's verifier as a fixture.

- [ ] **Step 2: Link CommonCrypto and confirm the tests fail**

Add `.linkedFramework("Security")` and `.linkedLibrary("CommonCrypto")` where supported by the installed SDK, then run: `swift test --filter Office2013KDFTests`

Expected: compilation fails because the KDF and verifier are missing.

- [ ] **Step 3: Implement the ECMA-376 derivation exactly**

```swift
public enum Office2013KDF {
    static let verifierInputBlockKey: [UInt8] = [0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79]
    static let verifierHashBlockKey: [UInt8] = [0xD7, 0xAA, 0x0F, 0x6D, 0x30, 0x61, 0x34, 0x4E]

    public static func passwordBytes(_ password: String) -> [UInt8] {
        Array(password.utf16).flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
    }
}
```

Implement `H0 = SHA512(salt || UTF16LE(password))`; for `i` in `0..<spinCount`, compute `H = SHA512(littleEndianUInt32(i) || H)`. Derive each verifier key using `SHA512(H || blockKey)`, truncate to 32 bytes, and decrypt verifier fields with AES-256-CBC using the salt truncated/padded to a 16-byte IV. Hash the 16-byte decrypted verifier with SHA-512 and constant-time compare the first 32 decrypted verifier-hash bytes required by the serialized hash.

- [ ] **Step 4: Run known-answer and wrong-password tests**

Run: `swift test --filter Office2013KDFTests`

Expected: correct candidate passes, case-changed and malformed candidates fail, and the process remains bounded at the maximum accepted spin count.

- [ ] **Step 5: Commit the CPU oracle**

```bash
git add Package.swift Sources/OfficeCrypto/Office2013KDF.swift Sources/OfficeCrypto/CPUOffice2013Verifier.swift Tests/OfficeCryptoTests Tests/Fixtures/README.md
git commit -m "feat: verify Office 2013 passwords on CPU"
```

### Task 4: Deterministic Candidate Sources and Checkpoints

**Files:**
- Create: `Sources/Recovery/CandidateBatch.swift`
- Create: `Sources/Recovery/CandidateSources.swift`
- Create: `Sources/Recovery/Checkpoint.swift`
- Create: `Tests/RecoveryTests/CandidateSourcesTests.swift`
- Create: `Tests/RecoveryTests/CheckpointTests.swift`

**Interfaces:**
- Produces: `protocol CandidateSource { mutating func nextBatch(limit:) throws -> CandidateBatch? }`
- Produces: `CandidateBatch(startCursor:candidates:)`
- Produces: `RecoveryCheckpoint.load(from:matching:) throws` and `.saveAtomically(to:) throws`

- [ ] **Step 1: Write deterministic ordering and resume tests**

```swift
func testMaskSourceResumesAtExactCursor() throws {
    var source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]], cursor: 2)
    XCTAssertEqual(try source.nextBatch(limit: 2)?.candidates, ["b0", "b1"])
}

func testCheckpointRejectsDifferentVerifierFingerprint() throws {
    let checkpoint = RecoveryCheckpoint(fingerprint: "aaa", stage: "mask-1", cursor: 42, tested: 42)
    XCTAssertThrowsError(try checkpoint.validate(fingerprint: "bbb", configurationDigest: checkpoint.configurationDigest))
}
```

- [ ] **Step 2: Run recovery-source tests and verify failure**

Run: `swift test --filter CandidateSourcesTests && swift test --filter CheckpointTests`

Expected: compilation fails because candidate and checkpoint types do not exist.

- [ ] **Step 3: Implement stable sources and atomic checkpoint JSON**

```swift
public struct CandidateBatch: Sendable {
    public let startCursor: UInt64
    public let candidates: [String]
}

public protocol CandidateSource: Sendable {
    var stageID: String { get }
    var cursor: UInt64 { get }
    mutating func nextBatch(limit: Int) throws -> CandidateBatch?
}
```

Implement streamed UTF-8 wordlists with a byte-offset cursor, deterministic mutations with a `(baseCursor, ruleIndex)` cursor, and mixed-radix masks with overflow-checked `UInt64` search sizes. Checkpoints use versioned `Codable` JSON, SHA-256 fingerprints of verifier parameters and recovery configuration, `FileHandle.synchronize()`, then an atomic rename.

- [ ] **Step 4: Run ordering, overflow, interruption, and resume tests**

Run: `swift test --filter RecoveryTests`

Expected: all tests pass; resuming produces the same next candidate with no skipped range.

- [ ] **Step 5: Commit candidate and checkpoint support**

```bash
git add Sources/Recovery Tests/RecoveryTests
git commit -m "feat: add resumable candidate pipeline"
```

### Task 5: Recovery Engine, Progress, Cancellation, and Thermal Response

**Files:**
- Create: `Sources/Recovery/RecoveryEngine.swift`
- Create: `Tests/RecoveryTests/RecoveryEngineTests.swift`
- Modify: `Sources/XLSXRescueCLI/main.swift`

**Interfaces:**
- Consumes: `CandidateSource`, `Office2013Parameters`, verifier backend
- Produces: `protocol CandidateVerifier { func matchingIndex(in:parameters:) async throws -> Int? }`
- Produces: `RecoveryEngine.run(source:parameters:checkpointURL:) async throws -> RecoveryResult`

- [ ] **Step 1: Write tests with a fake verifier and clock**

```swift
func testStopsOnMatchAndReportsCandidate() async throws {
    let verifier = FakeVerifier(match: "b1")
    let result = try await RecoveryEngine(verifier: verifier, batchSize: 2)
        .run(source: MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]]),
             parameters: .fixture, checkpointURL: nil)
    XCTAssertEqual(result, .found("b1"))
}

func testCancellationSavesNextUntestedCursor() async throws {
    // Cancel after one completed batch and assert checkpoint.cursor equals 2.
}
```

- [ ] **Step 2: Run the engine tests and confirm failure**

Run: `swift test --filter RecoveryEngineTests`

Expected: compilation fails because `RecoveryEngine` and `CandidateVerifier` are missing.

- [ ] **Step 3: Implement bounded asynchronous recovery**

```swift
public protocol CandidateVerifier: Sendable {
    func matchingIndex(in candidates: [String], parameters: Office2013Parameters) async throws -> Int?
}

public enum RecoveryResult: Equatable, Sendable {
    case found(String)
    case exhausted(tested: UInt64)
}
```

Use one candidate-production task and one verification task with at most two resident batches. Emit a redacted `ProgressSnapshot` once per second. Install `SIGINT`/`SIGTERM` handlers through `DispatchSourceSignal`, check `ProcessInfo.processInfo.thermalState` between batches, reduce batch concurrency for `.serious`, and checkpoint then stop for `.critical`.

- [ ] **Step 4: Run engine tests and a synthetic CLI recovery**

Run: `swift test --filter RecoveryEngineTests`

Expected: match, exhaustion, cancellation, checkpoint, and thermal-policy tests pass; output contains rate and count but no candidate text.

- [ ] **Step 5: Commit orchestration**

```bash
git add Sources/Recovery/RecoveryEngine.swift Sources/XLSXRescueCLI/main.swift Tests/RecoveryTests/RecoveryEngineTests.swift
git commit -m "feat: orchestrate cancellable password recovery"
```

### Task 6: Specialized Metal Verifier and Runtime Backend Selection

**Files:**
- Create: `Sources/MetalVerifier/Office2013Verifier.metal`
- Create: `Sources/MetalVerifier/MetalOffice2013Verifier.swift`
- Create: `Sources/MetalVerifier/BackendSelector.swift`
- Create: `Tests/MetalVerifierTests/MetalEquivalenceTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `CandidateVerifier`, `CPUOffice2013Verifier`, `Office2013Parameters`
- Produces: `MetalOffice2013Verifier: CandidateVerifier`
- Produces: `BackendSelector.select(parameters:) async throws -> any CandidateVerifier`

- [ ] **Step 1: Write CPU/Metal equivalence and fallback tests**

```swift
func testMetalMatchesCPUAcrossCandidateLengths() async throws {
    try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil)
    let candidates = deterministicCandidates(seed: 0x2013, counts: 512, lengths: 0...32)
    let cpu = try await CPUOffice2013BatchVerifier().matchingIndex(in: candidates, parameters: .fixture)
    let gpu = try await MetalOffice2013Verifier().matchingIndex(in: candidates, parameters: .fixture)
    XCTAssertEqual(gpu, cpu)
}

func testSelectorFallsBackWhenMetalIsUnavailableOrMismatches() async throws {
    let selected = try await BackendSelector(device: nil).select(parameters: .fixture)
    XCTAssertTrue(selected is CPUOffice2013BatchVerifier)
}
```

- [ ] **Step 2: Add the Metal resource target and verify tests fail**

Configure the `.metal` file as a processed SwiftPM resource and run: `swift test --filter MetalEquivalenceTests`

Expected: compilation fails because the Metal verifier types are missing.

- [ ] **Step 3: Implement the fixed-layout Metal batch ABI**

```swift
struct CandidateRecord {
    var utf16Length: UInt32
    var words: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
}

struct MatchResult {
    var index: UInt32   // UInt32.max means no match
}
```

In Metal, implement SHA-512 message scheduling and compression with 64-bit rotates, the 100,000 little-endian counter iterations, verifier block-key derivation, AES-256 key expansion/CBC decrypt for the two verifier fields, and an atomic minimum on matching candidate indices. Support UTF-16LE candidates up to 32 code units in the first kernel. Dispatch one thread per candidate using `.storageModeShared` buffers and zero buffers after command completion.

- [ ] **Step 4: Implement calibration and fail-closed equivalence selection**

Run a 256-candidate correctness probe containing a known match through both backends. If results differ or Metal reports an error, return CPU. Otherwise benchmark three warmed batches, select Metal only when median candidates/second exceeds CPU by at least 10%, and report only backend name and rate.

- [ ] **Step 5: Run equivalence tests and release benchmarks**

Run: `swift test --filter MetalEquivalenceTests`

Run: `swift run -c release xlsx-rescue benchmark --fixture Tests/Fixtures/office2013.hash --seconds 10`

Expected: all equivalence cases pass; selector chooses the measured faster backend without exposing the verifier.

- [ ] **Step 6: Commit Metal acceleration**

```bash
git add Package.swift Sources/MetalVerifier Tests/MetalVerifierTests
git commit -m "feat: accelerate Office 2013 verification with Metal"
```

### Task 7: Read-Only Compound File and Agile Encryption Parsing

**Files:**
- Create: `Sources/OfficeContainer/CompoundFile.swift`
- Create: `Sources/OfficeContainer/AgileEncryptionInfo.swift`
- Create: `Tests/OfficeContainerTests/CompoundFileTests.swift`

**Interfaces:**
- Produces: `CompoundFile.openReadOnly(_:) throws -> CompoundFile`
- Produces: `CompoundFile.readStream(named:maxBytes:) throws -> Data`
- Produces: `AgileEncryptionInfo.parse(_:) throws -> AgileEncryptionDescriptor`
- Produces: `AgileEncryptionDescriptor.passwordParameters -> Office2013Parameters`

- [ ] **Step 1: Write fixture and hostile-container tests**

```swift
func testReadsEncryptionStreams() throws {
    let file = try CompoundFile.openReadOnly(fixtureURL("known-password.xlsx"))
    XCTAssertFalse(try file.readStream(named: "EncryptionInfo", maxBytes: 1_048_576).isEmpty)
    XCTAssertFalse(try file.readStream(named: "EncryptedPackage", maxBytes: 64).isEmpty)
}

func testRejectsSectorChainCycle() {
    XCTAssertThrowsError(try CompoundFile.openReadOnly(fixtureURL("sector-cycle.cfb")))
}
```

- [ ] **Step 2: Run container tests and verify failure**

Run: `swift test --filter CompoundFileTests`

Expected: compilation fails because `CompoundFile` is missing.

- [ ] **Step 3: Implement bounds-checked CFB traversal**

Open with `open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)`, capture device/inode/size, and use `pread` only. Parse header byte order, sector shifts, DIFAT, FAT, miniFAT, directory entries, and UTF-16 stream names. Cap chain traversal at the total sector count and reject cycles, out-of-range sectors, arithmetic overflow, duplicate required streams, and oversized `EncryptionInfo`.

- [ ] **Step 4: Parse Agile XML without external entities**

Use `XMLParser`, disable external entity resolution, permit only the expected encryption namespaces/elements, and validate `SHA512`, `AES`, `CBC`, 256-bit keys, block size 16, salt size 16, and spin count bounds. Decode Base64 with exact post-decode lengths and map verifier fields into `Office2013Parameters`.

- [ ] **Step 5: Run valid, truncated, cyclic, and malicious XML tests**

Run: `swift test --filter OfficeContainerTests`

Expected: valid fixture parameters match its extracted verifier; every corrupt fixture fails without excessive allocation or source mutation.

- [ ] **Step 6: Commit read-only workbook inspection**

```bash
git add Sources/OfficeContainer/CompoundFile.swift Sources/OfficeContainer/AgileEncryptionInfo.swift Tests/OfficeContainerTests
git commit -m "feat: inspect encrypted Office containers safely"
```

### Task 8: Streaming Package Decryption and Transactional Export

**Files:**
- Create: `Sources/OfficeContainer/EncryptedPackage.swift`
- Create: `Sources/OfficeContainer/OOXMLValidator.swift`
- Create: `Tests/OfficeContainerTests/PackageDecryptTests.swift`
- Modify: `Sources/XLSXRescueCLI/main.swift`

**Interfaces:**
- Consumes: `CompoundFile`, `AgileEncryptionDescriptor`, password bytes
- Produces: `EncryptedPackage.decrypt(from:descriptor:password:temporaryURL:) throws`
- Produces: `OOXMLValidator.validate(_:) throws`
- Produces: `TransactionalExporter.publish(temp:to:overwrite:) throws`

- [ ] **Step 1: Write decryption, wrong-password, and source-integrity tests**

```swift
func testDecryptsKnownWorkbookWithoutChangingSource() throws {
    let source = fixtureURL("known-password.xlsx")
    let before = try Data(contentsOf: source)
    let output = temporaryDirectory.appendingPathComponent("copy.xlsx")
    try decryptFixture(source: source, password: "Correct Horse", output: output)
    XCTAssertEqual(try Data(contentsOf: source), before)
    XCTAssertNoThrow(try OOXMLValidator.validate(output))
}

func testWrongPasswordPublishesNothing() throws {
    XCTAssertThrowsError(try decryptFixture(source: fixtureURL("known-password.xlsx"), password: "wrong", output: output))
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
}
```

- [ ] **Step 2: Run package tests and verify failure**

Run: `swift test --filter PackageDecryptTests`

Expected: compilation fails because decryptor and validator are missing.

- [ ] **Step 3: Implement ECMA-376 streaming package decryption**

Verify the password first. Decrypt the encrypted package key from the Agile descriptor. Read the 8-byte little-endian plaintext package length, then process 4,096-byte encrypted segments. For segment `n`, derive the IV from `SHA512(keyDataSalt || littleEndianUInt32(n))`, truncate to 16 bytes, AES-CBC decrypt, and write no more than the declared remaining plaintext length. Reject inconsistent length, padding, short read, or trailing structure.

- [ ] **Step 4: Implement minimal ZIP/OOXML validation and atomic publication**

Validate ZIP local/central directory bounds and require `[Content_Types].xml`, `_rels/.rels`, and `xl/workbook.xml`. Create the temporary file with mode `0600` in the destination directory, `fsync` it, reject source/output identity, and publish with an atomic rename. If `overwrite` is false, fail when the destination exists; if true, require an explicit CLI flag and still reject the source path.

- [ ] **Step 5: Run export and corruption tests**

Run: `swift test --filter PackageDecryptTests`

Expected: known fixture decrypts and validates; wrong password, malformed package, existing destination, and source-equals-output publish nothing; source digest remains unchanged.

- [ ] **Step 6: Commit safe export**

```bash
git add Sources/OfficeContainer/EncryptedPackage.swift Sources/OfficeContainer/OOXMLValidator.swift Sources/XLSXRescueCLI/main.swift Tests/OfficeContainerTests/PackageDecryptTests.swift
git commit -m "feat: export verified unencrypted workbook copies"
```

### Task 9: End-to-End Commands, Documentation, and Release Verification

**Files:**
- Modify: `Sources/XLSXRescueCLI/CommandRouter.swift`
- Modify: `Sources/XLSXRescueCLI/main.swift`
- Modify: `Tests/CLITests/CommandRouterTests.swift`
- Create: `README.md`

**Interfaces:**
- Consumes: all prior public interfaces
- Produces: complete `inspect`, `recover`, `recover-hash`, `decrypt`, and internal `benchmark` workflows

- [ ] **Step 1: Write end-to-end CLI tests**

```swift
func testRecoverHashFindsSyntheticPasswordWithoutEchoingItInProgress() async throws {
    let run = try await CLIRunner.run(
        ["recover-hash", "--hash-stdin", "--wordlist", fixture("words.txt")],
        standardInput: Self.fixtureVerifier + "\n"
    )
    XCTAssertEqual(run.exitCode, 0)
    XCTAssertTrue(run.standardOutput.contains("Password recovered"))
    XCTAssertFalse(run.standardError.contains(Self.fixtureVerifier))
}

func testInspectReportsParametersButNotVerifierBytes() async throws {
    let run = try await CLIRunner.run(["inspect", fixture("known-password.xlsx")])
    XCTAssertTrue(run.standardOutput.contains("Office 2013"))
    XCTAssertTrue(run.standardOutput.contains("100000 iterations"))
    XCTAssertFalse(run.standardOutput.contains("encryptedVerifier"))
}
```

- [ ] **Step 2: Wire complete commands and stable exit codes**

Use exit `0` for success/recovered, `1` for exhausted search, `2` for usage errors, `3` for unsupported encryption, `4` for invalid/corrupt input, `5` for I/O/export failure, and `130` for user cancellation. Print progress to stderr and machine-useful final status to stdout. Reveal a recovered password only after an interactive confirmation or write it to a new mode-`0600` result file.

- [ ] **Step 3: Document safe usage and realistic limits**

Document these exact patterns:

```bash
printf '%s\n' "$OFFICE_VERIFIER" | swift run -c release xlsx-rescue recover-hash --hash-stdin --wordlist /path/to/words.txt
swift run -c release xlsx-rescue inspect /path/to/encrypted.xlsx
swift run -c release xlsx-rescue decrypt /path/to/encrypted.xlsx --password-stdin --output /path/to/decrypted-copy.xlsx
```

Warn that putting a literal verifier or password into a command stores it in shell history; the example environment variable must be populated through a secure interactive method. Explain exhaustive-search size, measured throughput, thermal behavior, checkpoints, authorization, and the absence of a recovery guarantee.

- [ ] **Step 4: Run the complete test suite and release build**

Run: `swift test --parallel`

Run: `swift build -c release`

Expected: all tests pass and the release executable builds without warnings.

- [ ] **Step 5: Run a clean end-to-end fixture recovery and export**

Run recovery against the disposable Office 2013 fixture, interrupt once, resume from its checkpoint, recover the known password, decrypt to a new path, and compare the decrypted package's workbook XML with the original pre-encryption fixture.

Expected: resume begins at the first untested cursor; the password verifies on CPU; the copy opens as OOXML; the encrypted source digest is unchanged.

- [ ] **Step 6: Record M4 release measurements**

Run three 30-second CPU and Metal trials after one warm-up trial. Record median candidates/second, batch size, macOS version, device name, and thermal state in `README.md`. Do not record the verifier, candidates, or password.

- [ ] **Step 7: Commit the completed utility**

```bash
git add Sources Tests README.md Package.swift
git commit -m "feat: complete Office password recovery utility"
```

## Final Verification Checklist

- [ ] `swift test --parallel` passes.
- [ ] `swift build -c release` succeeds without warnings.
- [ ] The CPU known-answer verifier accepts only the fixture password.
- [ ] Metal and CPU match across deterministic randomized batches and boundary lengths.
- [ ] Runtime selection falls back to CPU after any Metal mismatch or failure.
- [ ] Checkpoint resume begins at the exact first untested candidate.
- [ ] Logs and errors contain no verifier, password, candidate, or key material.
- [ ] Wrong passwords and corrupt inputs never publish output.
- [ ] Decrypted output passes OOXML validation and opens independently.
- [ ] The encrypted source digest remains unchanged.
- [ ] README reports measured M4 performance and realistic search-space limits.
