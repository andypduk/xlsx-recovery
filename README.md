# XLSX Rescue

Native Swift/Metal utility for authorized recovery of Office 2013 Agile Encryption passwords on Apple Silicon macOS. It preserves the encrypted source and writes a separate unencrypted `.xlsx` only after password and OOXML validation.

## macOS app

The native **XLSX Rescue** dashboard supports the complete local workflow:

- Choose or drop an encrypted `.xlsx`, or paste a visible `$office$` verifier.
- Select a UTF-8 wordlist or configure a bounded brute-force search.
- See tested candidates, speed, elapsed time, ETA, Metal/CPU backend, and thermal state.
- Pause at a checkpoint, resume without retesting earlier candidates, or cancel safely.
- Reveal and explicitly copy a recovered password.
- Save a separate validated, unencrypted workbook copy.

Open the supplied app bundle, or build it from source:

```bash
xcodegen generate --spec App/project.yml
xcodebuild build -project App/XLSXRescueApp.xcodeproj -scheme XLSXRescueApp -destination 'platform=macOS,arch=arm64'
```

The personal build uses bundle identifier `com.andyg.xlsxrescue`, automatic signing, Hardened Runtime, and no extra entitlements. If `security find-identity -v -p codesigning` reports no valid identity, add an Apple Development certificate in Xcode under **Settings → Accounts → Manage Certificates**, then rebuild. An ad-hoc-signed local build remains usable on the Mac that built it.

The app performs no network requests. It opens the source workbook read-only and writes decrypted data only to a separate location selected in the save panel.

## Build

```bash
swift build -c release
```

## Inspect

```bash
xlsx-rescue inspect /path/to/encrypted.xlsx
```

## Recover from a verifier

Keep verifier strings out of shell history:

```bash
xlsx-rescue recover-hash --hash-stdin --wordlist /path/to/words.txt --show-password
```

Paste or pipe the verifier through standard input. Without a wordlist, bounded brute force defaults to lowercase letters and digits, lengths 1 through 6:

```bash
xlsx-rescue recover-hash --hash-stdin --charset 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#' --min-length 1 --max-length 7 --show-password
```

An exhaustive search grows exponentially. A strong random unknown password may not be recoverable on any practical hardware.

## Recover directly from a workbook

```bash
xlsx-rescue recover /path/to/encrypted.xlsx --wordlist /path/to/words.txt --show-password
```

## Export an unencrypted copy

```bash
xlsx-rescue decrypt /path/to/encrypted.xlsx --password-stdin --output /path/to/decrypted-copy.xlsx
```

The password is read with terminal echo disabled. The source path cannot be used as the output path. Existing output is preserved unless `--overwrite` is explicit.

## Implementation notes

- The CPU verifier is the correctness oracle.
- Metal performs the 100,000-round SHA-512 hot loop in shared Apple Silicon memory.
- Metal uses 4,096-candidate batches to amortize command-buffer and buffer setup; CPU fallback remains at 256 and serious thermal pressure halves either batch size.
- Metal results are confirmed with CPU AES-256-CBC verification.
- Metal falls back to CPU for unsupported candidate lengths or initialization failure.
- Wordlists are streamed in 64 KiB chunks and tested in bounded batches; they are never loaded or counted in full.
- Individual wordlist entries are limited to 4 KiB so malformed lines cannot grow memory without bound.
- Critical thermal pressure stops recovery at a batch boundary.
- No verifier, password, candidate, derived key, or decrypted content is logged.

The algorithm follows Microsoft's MS-OFFCRYPTO Agile Encryption specification. Compatibility is checked against Hashcat mode 9600's independent self-test vector.
