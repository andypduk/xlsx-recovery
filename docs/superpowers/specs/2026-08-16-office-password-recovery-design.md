# Office Password Recovery Utility Design

## Purpose

Build a native macOS command-line utility in Swift for recovering access to an authorized, password-encrypted `.xlsx` file and exporting a separate unencrypted copy. The initial target is an Apple M4 MacBook Air with 24 GB unified memory running macOS Tahoe 26.6.1.

The utility does not bypass encryption. It tests password candidates, derives the Office encryption key for each candidate, verifies a match cryptographically, decrypts the package after a match, and preserves the original file unchanged.

## Scope

Version 1 will:

- Inspect an encrypted Office file and report its container and encryption parameters.
- Support modern ECMA-376 Agile Encryption used by password-to-open `.xlsx` files.
- Import a Hashcat-compatible `$office$` verifier through standard input or a protected file, initially specializing the Office 2013, SHA-512, 100,000-iteration, 256-bit AES case.
- Reject unsupported or malformed encryption formats with a precise diagnostic.
- Run staged password recovery from supplied wordlists and bounded generated candidates.
- Apply configurable mutations such as case changes, common suffixes, digits, years, and symbols.
- Use Metal compute kernels where profiling demonstrates a benefit, with a CPU implementation as the correctness reference and fallback.
- Show candidate count, rate, elapsed time, current stage, and an honest ETA when the search space is bounded.
- Save and resume checkpoints without storing recovered plaintext or key material.
- Verify a recovered password before reporting success.
- Decrypt to a new `.xlsx` file, validate that it is a ZIP/OOXML package, and never overwrite the source.

Version 1 will not:

- Promise recovery of arbitrary strong passwords.
- Distribute password lists or obtain leaked credentials.
- Attack remote services or files without authorization.
- Modify workbook or worksheet protection independently of password-to-open encryption.
- Provide a graphical interface.
- Support every historical Office encryption variant.

## User Interface

The executable, tentatively named `xlsx-rescue`, will expose focused commands:

```text
xlsx-rescue inspect <input.xlsx>
xlsx-rescue recover <input.xlsx> [candidate options] [--checkpoint <path>]
xlsx-rescue recover-hash --hash-stdin [candidate options] [--checkpoint <path>]
xlsx-rescue decrypt <input.xlsx> --password-stdin --output <copy.xlsx>
```

Passwords and Office verifier strings will not be accepted as ordinary command-line arguments because those may appear in shell history and process listings. Interactive entry, standard input, and permission-checked input files will be supported. Recovery options will include wordlist paths, mutation profiles, character sets, minimum and maximum generated lengths, candidate limits, and time limits. Unbounded exhaustive searches will require an explicit confirmation flag.

## Architecture

### Compound File Reader

Encrypted OOXML documents are stored in an OLE Compound File Binary container rather than as a normal ZIP archive. A read-only parser will locate and bounds-check the `EncryptionInfo` and `EncryptedPackage` streams. It will expose byte ranges without loading the full workbook into memory.

### Office Encryption Model

An Agile Encryption parser will decode the encryption descriptor, validate supported combinations, and produce an immutable parameter model containing salts, spin count, hash algorithm, cipher algorithm, key size, block size, and encrypted verifier fields.

The reference verifier will implement the ECMA-376 password normalization, iterative hashing, key derivation, verifier decryption, and verifier-hash comparison. Cryptographic comparisons will be constant-time where applicable.

A separate `$office$` parser will decode the Hashcat-compatible representation into the same immutable parameter model. It will strictly validate field count, version, numeric ranges, declared lengths, and hexadecimal data before allocating buffers. The supplied Office 2013 verifier will be used as a private local test input and will not be embedded in source code, fixtures, logs, documentation, or checkpoints.

### Candidate Pipeline

Candidate sources will conform to one batching interface:

- Streamed wordlists.
- Deterministic mutation rules.
- Masks such as known prefixes or digit positions.
- Bounded brute-force character sets.

Every source will have a stable stage identifier and numeric cursor so a checkpoint can resume without ambiguity. Candidates will be encoded and normalized once per batch. Duplicate suppression will be bounded so it cannot consume unbounded memory.

### Compute Backends

The CPU backend will be the source of truth and will be covered by known-answer tests. It will use Swift concurrency to keep parsing, candidate production, and verification stages back-pressured.

The Metal backend will process large, fixed-layout candidate batches. The first specialized kernel will target the supplied verifier class: Office 2013 Agile Encryption using SHA-512, 100,000 iterations, a 256-bit AES key, and a 16-byte salt. Kernels will perform the supported password hashing and iterative derivation work, returning only possible match indices for CPU confirmation. Pipeline specialization constants will cover bounded candidate lengths and later-supported parameter variants. Buffers will use Apple Silicon shared storage to avoid unnecessary copies.

Metal will not be assumed faster. Startup calibration will compare CPU and GPU throughput for the detected encryption parameters, then select the faster backend. The UI will report the selected backend and measured rate.

### Decryption and Export

After password verification, a streaming decryptor will derive the package key, decrypt `EncryptedPackage` block by block, remove encryption padding according to the format, and write to a temporary file beside the requested output when possible. It will validate ZIP signatures and essential OOXML entries before atomically moving the temporary file to the final output path. Existing output files will not be replaced unless the user gives an explicit overwrite option.

### Checkpoints

Checkpoint files will contain the input file identity, encryption-parameter fingerprint, recovery configuration, stage identifier, cursor, elapsed time, and tested count. They will not contain passwords, derived keys, decrypted bytes, or recent candidate strings. Resume will fail safely if the input or configuration does not match.

## Data Flow

1. Open the source read-only and parse its compound-file directory, or securely read and validate a `$office$` verifier.
2. Convert the encryption descriptor or verifier into the common parameter model.
3. Benchmark the eligible CPU and Metal verifier paths.
4. Stream candidate batches through the chosen backend.
5. Confirm any GPU-reported match with the independent CPU verifier.
6. Save progress periodically and on graceful interruption.
7. On success, request the user-selected output path.
8. Stream-decrypt into a temporary output, validate it, then publish the unencrypted copy atomically.

## Safety and Failure Handling

- The source file is always opened read-only.
- File sizes, offsets, sector chains, XML values, spin counts, and allocation sizes are bounds-checked.
- Unsupported algorithms stop before recovery begins.
- Cancellation and thermal-pressure signals stop cleanly after the active batch and save a checkpoint.
- Metal initialization or execution failure falls back to the CPU backend with a warning.
- Partial decrypted files retain a temporary suffix and are removed or preserved for diagnosis according to an explicit option.
- Logs redact candidate passwords, derived keys, and decrypted data.
- Verifier input is redacted from logs and crash diagnostics, and permission-checked verifier files must not be group- or world-readable unless the user explicitly overrides the warning.
- A success result requires verifier confirmation and validation of the decrypted OOXML package.

## Performance Strategy

Performance work will be measurement-driven. Initial benchmarks will compare batch sizes and CPU/GPU execution for the exact spin count and hash algorithm in the target file. Candidate generation will overlap compute without creating unbounded queues. The default profile will avoid sustained maximum load when macOS reports serious thermal pressure; an explicit performance mode may permit higher sustained utilization.

The program will calculate the size of each bounded search before starting. It will warn when the measured completion estimate is unrealistic. With no password clues, the recommended default sequence is a user-supplied general wordlist, structured mutations, common date patterns, and only then short-length brute force.

## Testing

Tests will include:

- Known-answer tests for password encoding, iterative hashing, key derivation, verifier checks, and block decryption.
- Fixtures created with known passwords and supported Agile Encryption settings.
- Parser tests for valid and malformed `$office$` verifier strings, including the Office 2013 parameter class.
- Negative tests for wrong passwords, corrupt descriptors, malicious sector chains, truncated streams, and unsupported algorithms.
- Equivalence tests requiring CPU and Metal backends to return identical results across randomized candidate batches.
- Checkpoint interruption and deterministic-resume tests.
- Export validation by reopening the resulting ZIP package and checking required OOXML entries.
- Source-integrity tests proving the original file's bytes and metadata content are not changed.
- Performance benchmarks on the target M4 MacBook Air.

Real personal documents will not be committed as fixtures.

## Acceptance Criteria

The first release is complete when it can inspect a supported encrypted fixture, import a compatible `$office$` verifier securely, recover a known test password from staged candidates, resume the same search from a checkpoint, produce CPU/Metal-equivalent verification results for the Office 2013 specialized path, decrypt to a valid unencrypted `.xlsx` copy when the source workbook is available, and pass a release build and automated test suite on Apple Silicon macOS.

The documentation must state measured candidates per second for representative fixtures and must not imply that strong unknown passwords are guaranteed to be recoverable.
