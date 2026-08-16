# XLSX Rescue

Native Swift/Metal utility for authorized recovery of Office 2013 Agile Encryption passwords on Apple Silicon macOS. It preserves the encrypted source and writes a separate unencrypted `.xlsx` only after password and OOXML validation.

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
- Metal results are confirmed with CPU AES-256-CBC verification.
- Metal falls back to CPU for unsupported candidate lengths or initialization failure.
- Critical thermal pressure stops recovery at a batch boundary.
- No verifier, password, candidate, derived key, or decrypted content is logged.

The algorithm follows Microsoft's MS-OFFCRYPTO Agile Encryption specification. Compatibility is checked against Hashcat mode 9600's independent self-test vector.
