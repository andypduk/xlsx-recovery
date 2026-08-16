# XLSX Rescue macOS App Design

## Purpose

Build a native SwiftUI macOS application around the existing XLSX Rescue engine. The first release is for personal use on an Apple M4 MacBook Air with 24 GB unified memory running macOS Tahoe 26.6.1. It will be development-signed with the user's Apple Developer identity and structured for later Developer ID signing and notarization.

## Product Scope

The application supports the complete authorized recovery workflow:

- Select or drop an encrypted `.xlsx` workbook.
- Paste and visibly inspect a Hashcat-compatible `$office$` verifier.
- Inspect a workbook and extract supported Office 2013 Agile Encryption parameters.
- Configure wordlist or bounded brute-force recovery.
- Run CPU/Metal recovery with detailed live progress.
- Pause to a checkpoint, resume at the next untested candidate, or cancel safely.
- Reveal and copy a recovered password.
- Decrypt and save a separate validated, unencrypted `.xlsx` copy.

It does not promise recovery of arbitrary strong passwords, download password lists, modify the encrypted source, or run attacks against remote services.

## Application Structure

An Xcode macOS application project will contain a SwiftUI app target and unit-test target. The app target imports the existing local Swift package products: `OfficeCrypto`, `Recovery`, `MetalVerifier`, and `OfficeContainer`. The CLI remains available and unchanged except for compatible shared-model improvements required by the GUI.

Primary files:

- `XLSXRescueApp.swift`: application lifecycle and command menu.
- `RecoveryDashboardView.swift`: single-window dashboard composition.
- `RecoveryViewModel.swift`: `@MainActor` state machine and task ownership.
- `RecoveryConfiguration.swift`: validated wordlist and brute-force configuration.
- `ProgressPresentation.swift`: deterministic percentage, speed, duration, and ETA formatting.
- `FileSelectionService.swift`: `NSOpenPanel`, `NSSavePanel`, and security-scoped URL handling.
- `AppRecoveryRunner.swift`: adapter from UI configuration to engine candidate sources and checkpoints.
- `ResultPanel.swift`: password reveal/copy and unencrypted-export actions.
- `AppError.swift`: actionable, redacted user-facing errors.

The cryptographic implementation remains in the existing package targets. Views do not call cryptographic APIs directly.

## Dashboard Layout

The selected Recovery Dashboard is a single resizable macOS window.

The top area contains two input modes:

- Workbook: drag/drop target, Choose Workbook button, file name, and detected encryption summary.
- Office Hash: visible, selectable multi-line field with Paste, Clear, and Validate controls.

The configuration area contains a segmented recovery-method control:

- Wordlist: file chooser, file name, and readable-file validation.
- Brute Force: visible character set, minimum length, maximum length, calculated search-space size, and feasibility warning.

The active-recovery panel contains:

- Progress bar and bounded percentage when total work is known.
- Current stage and candidate length.
- Candidates tested, candidates per second, elapsed time, and ETA.
- Selected backend (`Metal` or `CPU`) and current thermal state.
- Pause/Resume and Cancel controls.

The result panel contains a masked-by-default recovered password field, Reveal, Copy, Reset, and Save Unencrypted Copy buttons. The Office verifier remains visible because the user explicitly requested visible hash handling.

## State Model

`RecoveryViewModel` owns one state value:

```swift
enum RecoverySessionState: Equatable {
    case idle
    case inspecting
    case ready(InputSummary)
    case recovering(ProgressSnapshot)
    case paused(CheckpointSummary)
    case recovered(RecoveryResultSummary)
    case decrypting
    case completed(output: URL)
    case failed(AppError)
}
```

Only legal transitions are exposed as view-model actions. Starting recovery creates one structured `Task`. Pause requests cancellation at the next batch boundary and saves a checkpoint. Resume rebuilds the deterministic candidate source from the checkpoint. Cancel stops the task and leaves source and destination files unchanged. Reset cancels active work, clears UI password material, and returns to idle.

All engine callbacks cross to `MainActor` before mutating published UI state. Progress updates are throttled to a visually stable interval and never include candidate strings.

## Progress and ETA

The GUI calculates total candidates with overflow-checked mixed-radix arithmetic before recovery. Percentage and ETA appear only for bounded stages. Wordlists use total readable line count when known; otherwise they show indeterminate progress with tested count and measured rate.

Progress contains:

- aggregate tested count across stages;
- current-stage tested and total counts;
- measured candidates per second over a rolling interval;
- elapsed monotonic time;
- ETA based on remaining candidates and rolling rate; and
- backend and thermal-state labels.

The UI updates at most four times per second. It does not imply precision when rate samples are insufficient.

## Files and Security

- Use native `NSOpenPanel` and `NSSavePanel` controls.
- Accept `.xlsx` workbooks and ordinary wordlist files.
- Resolve and compare source/output file identities before export.
- Open encrypted workbooks read-only.
- Write decrypted content to a mode-`0600` temporary file, validate it as OOXML, then publish atomically.
- Never log Office verifiers, candidate passwords, recovered passwords, derived keys, or decrypted content.
- Keep password presentation masked until Reveal is selected.
- Copy only on explicit user action and show a non-blocking clipboard confirmation.
- Clear in-memory password presentation when Reset is selected or the application terminates.
- The visible verifier field is intentionally not a secure field; nearby help text notes that screen recordings can capture it.

## Signing and Entitlements

The first release uses automatic signing with the user's Apple Development identity and personal Team. The app uses the Hardened Runtime. App Sandbox is disabled for the personal build because the utility performs long-running compute and user-selected file operations; all file access is nevertheless constrained to explicit user selections.

No network, camera, microphone, contacts, calendar, accessibility, or automation entitlements are requested. A later direct-download release can switch to Developer ID Application signing and Apple notarization without changing the application architecture.

## Error Handling

Errors appear in a persistent dashboard banner with a short explanation and relevant recovery action. Detailed errors are redacted. Cases include:

- unsupported or malformed Office encryption;
- unreadable workbook or wordlist;
- invalid verifier syntax;
- empty or overflowing search spaces;
- Metal unavailable or failed, with transparent CPU fallback;
- serious or critical thermal pressure;
- checkpoint/input mismatch;
- wrong password;
- invalid decrypted OOXML; and
- destination exists or matches the source.

Critical thermal pressure pauses at the next batch boundary and saves a checkpoint rather than silently continuing.

## Testing

Unit tests cover:

- every legal and illegal state transition;
- workbook and visible-verifier validation;
- wordlist and brute-force configuration validation;
- exact search-space totals and overflow;
- progress, duration, percentage, speed, and ETA formatting;
- pause/checkpoint/resume at the next untested candidate;
- cancellation and reset clearing result state;
- redacted error presentation;
- source/output collision prevention; and
- mocked successful recovery and decrypt/export flows.

Existing cryptographic, Metal-equivalence, container, and CLI tests remain green. UI validation includes a Debug application build, an unsigned clean-room build with signing disabled, and a development-signed build when the configured identity is available.

## Acceptance Criteria

The design is complete when the app:

- launches as a native macOS SwiftUI application;
- accepts a workbook or visible Office verifier;
- validates and describes the supplied Office 2013 parameters;
- runs wordlist and bounded brute-force recovery;
- shows stable live progress, speed, elapsed time, ETA, backend, and thermal state;
- pauses, checkpoints, resumes, and cancels without skipping candidates;
- reveals and copies a recovered password only through explicit controls;
- exports a separate validated unencrypted workbook;
- preserves the encrypted source byte-for-byte;
- passes all package and app tests; and
- builds successfully with the user's Apple Development signing configuration.
