# XLSX Rescue macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a development-signed native SwiftUI macOS Recovery Dashboard around the existing Swift/Metal Office recovery engine.

**Architecture:** An XcodeGen-defined macOS app imports the existing local Swift package products. A `@MainActor` observable view model owns a strict session state machine, while `AppRecoveryRunner` translates UI configuration into existing candidate sources and recovery/decryption calls. SwiftUI remains presentation-only and uses native AppKit panels for user-selected file access.

**Tech Stack:** Swift 6, SwiftUI, Observation, AppKit, Xcode 26.6, XcodeGen, XCTest, existing OfficeCrypto/Recovery/MetalVerifier/OfficeContainer package targets, macOS Tahoe 26.6.1.

## Global Constraints

- Target Apple M4 MacBook Air with 24 GB unified memory and macOS Tahoe 26.6.1.
- Personal-use build uses automatic Apple Development signing when a Team is configured.
- Hardened Runtime enabled; App Sandbox disabled for the personal build.
- No network, automation, accessibility, camera, microphone, contacts, or calendar entitlements.
- Office verifier is intentionally visible; recovered password is masked until Reveal.
- Never log verifiers, candidates, passwords, keys, or decrypted content.
- Never overwrite or modify the encrypted source workbook.
- Existing CLI and package tests must remain green.

---

### Task 1: GUI Project Skeleton and Core Models

**Files:**
- Create: `App/project.yml`
- Create: `App/XLSXRescueApp/XLSXRescueApp.swift`
- Create: `App/XLSXRescueApp/RecoverySessionState.swift`
- Create: `App/XLSXRescueApp/RecoveryConfiguration.swift`
- Create: `App/XLSXRescueApp/Assets.xcassets/Contents.json`
- Create: `App/XLSXRescueApp/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `App/XLSXRescueAppTests/RecoveryConfigurationTests.swift`

**Interfaces:**
- Produces: `enum RecoverySessionState`
- Produces: `struct RecoveryConfiguration` with `validate()` and `totalCandidates`
- Produces: `XLSXRescueApp.xcodeproj`

- [ ] Write tests proving empty character sets, invalid length ranges, missing wordlists, and overflowing search spaces fail validation, while bounded configurations return exact totals.
- [ ] Run `xcodegen generate --spec App/project.yml` and `xcodebuild test -project App/XLSXRescueApp.xcodeproj -scheme XLSXRescueApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`; expect missing model failures.
- [ ] Implement `RecoveryConfiguration`, `RecoveryInput`, `RecoveryMethod`, `InputSummary`, `CheckpointSummary`, and `RecoveryResultSummary` as immutable `Sendable` value types.
- [ ] Implement the state enum exactly as specified and a minimal SwiftUI `App` scene displaying the current state.
- [ ] Regenerate the project and rerun the app model tests; expect all to pass.
- [ ] Commit with `git commit -m "feat: scaffold XLSX Rescue macOS app"`.

### Task 2: Progress Presentation and State Machine

**Files:**
- Create: `App/XLSXRescueApp/ProgressPresentation.swift`
- Create: `App/XLSXRescueApp/RecoveryViewModel.swift`
- Create: `App/XLSXRescueApp/AppError.swift`
- Create: `App/XLSXRescueAppTests/ProgressPresentationTests.swift`
- Create: `App/XLSXRescueAppTests/RecoveryViewModelTests.swift`

**Interfaces:**
- Produces: `ProgressPresentation.init(snapshot:stageTotal:aggregateTotal:)`
- Produces: `@MainActor @Observable final class RecoveryViewModel`
- Produces: legal actions `selectInput`, `validateHash`, `start`, `pause`, `resume`, `cancel`, `reset`, `export`

- [ ] Write exact formatting tests for `0`, `1_250`, and `12_500_000` candidates; zero and nonzero rates; bounded percentages; durations; and unavailable versus stable ETAs.
- [ ] Write state tests proving idle→ready→recovering→paused→recovering→recovered, failure recovery, cancel, and reset; assert illegal actions leave state unchanged.
- [ ] Run the focused tests and confirm the presentation and view-model types are missing.
- [ ] Implement deterministic formatters using `Duration`, `MeasurementFormatter`, and overflow-safe percentage calculations.
- [ ] Implement `RecoveryViewModel` with injected `RecoveryRunning`, one owned `Task`, throttled MainActor progress updates, password clearing on reset, and redacted `AppError` values.
- [ ] Rerun focused tests; expect all transitions and formatting cases to pass.
- [ ] Commit with `git commit -m "feat: add dashboard state and progress models"`.

### Task 3: File Selection and Recovery Adapter

**Files:**
- Create: `App/XLSXRescueApp/FileSelectionService.swift`
- Create: `App/XLSXRescueApp/AppRecoveryRunner.swift`
- Create: `App/XLSXRescueApp/ClipboardService.swift`
- Create: `App/XLSXRescueAppTests/AppRecoveryRunnerTests.swift`
- Modify: `Sources/Recovery/RecoveryEngine.swift`

**Interfaces:**
- Produces: `protocol RecoveryRunning`
- Produces: `AppRecoveryRunner.inspect`, `recover`, `pause`, `decrypt`
- Produces: progress containing stage totals, backend label, and thermal state

- [ ] Write adapter tests with the independent Office 2013 fixture verifier, a temporary wordlist, pause cancellation, deterministic resume, and mocked export.
- [ ] Extend engine progress with current-stage cursor/total where known and backend/thermal labels without including candidate text.
- [ ] Implement AppKit open/save panels restricted to `.xlsx` or ordinary files as appropriate; retain only explicit user selections.
- [ ] Implement the runner using `OfficeHashParser`, `CompoundFile`, `AgileEncryptionInfo`, `BackendSelector`, `RecoveryEngine`, `EncryptedPackage`, and `TransactionalExporter`.
- [ ] Implement explicit clipboard copy with a published confirmation timestamp; never copy automatically.
- [ ] Run package and app adapter tests; expect all to pass.
- [ ] Commit with `git commit -m "feat: connect macOS app to recovery engine"`.

### Task 4: Recovery Dashboard UI

**Files:**
- Create: `App/XLSXRescueApp/RecoveryDashboardView.swift`
- Create: `App/XLSXRescueApp/InputPanel.swift`
- Create: `App/XLSXRescueApp/ConfigurationPanel.swift`
- Create: `App/XLSXRescueApp/ActiveRecoveryPanel.swift`
- Create: `App/XLSXRescueApp/ResultPanel.swift`
- Create: `App/XLSXRescueApp/ErrorBanner.swift`
- Modify: `App/XLSXRescueApp/XLSXRescueApp.swift`

**Interfaces:**
- Consumes: `RecoveryViewModel`
- Produces: selected one-window Recovery Dashboard design

- [ ] Build the top input panel with workbook drop/chooser and a visible, selectable multiline Office verifier field with Paste, Clear, and Validate actions.
- [ ] Build wordlist and brute-force configuration controls with calculated search-space and feasibility warnings.
- [ ] Build the active panel with progress bar, stage, tested count, rate, elapsed, ETA, Metal/CPU backend, thermal state, Pause/Resume, and Cancel.
- [ ] Build the masked result field with Reveal, Copy, Reset, and Save Unencrypted Copy actions.
- [ ] Add VoiceOver labels, keyboard navigation, reduced-motion-safe transitions, minimum window size, and native macOS toolbar/menu commands.
- [ ] Build with signing disabled and inspect SwiftUI previews or the running Debug app at 100% and 200% window scaling.
- [ ] Commit with `git commit -m "feat: build SwiftUI recovery dashboard"`.

### Task 5: Personal Signing and Application Packaging

**Files:**
- Modify: `App/project.yml`
- Create: `App/XLSXRescueApp/XLSXRescueApp.entitlements`
- Create: `App/ExportOptions.plist`
- Modify: `README.md`

**Interfaces:**
- Produces: development-signed `XLSX Rescue.app`
- Produces: unsigned build path when no Team is configured

- [ ] Add bundle identifier `com.andyg.xlsxrescue`, automatic signing, Hardened Runtime, and empty least-privilege entitlements.
- [ ] Detect available signing identities with `security find-identity -v -p codesigning`; never store certificate material in the repository.
- [ ] Generate the project and run an unsigned clean build with `CODE_SIGNING_ALLOWED=NO`.
- [ ] If an Apple Development identity and Team are configured, build with automatic signing and verify with `codesign --verify --deep --strict --verbose=2` and `codesign -d --entitlements :-`.
- [ ] Copy the verified `.app` into `outputs/XLSX Rescue.app` and document launch, recovery, and export workflows.
- [ ] Commit with `git commit -m "build: package personal XLSX Rescue app"`.

### Task 6: Final Regression and Handoff

**Files:**
- Modify: `README.md`
- Modify: app or test files only for defects revealed by verification

**Interfaces:**
- Produces: verified personal-use macOS application and complete source branch

- [ ] Run `swift test --parallel`; expect every package test to pass.
- [ ] Run the complete Xcode app test suite with signing disabled; expect every app test to pass.
- [ ] Run `xcodebuild clean build` for macOS; expect `BUILD SUCCEEDED` with no warnings.
- [ ] Launch the app, validate a fixture verifier, run a small wordlist recovery, pause/resume once, reveal/copy the recovered fixture password, and reset.
- [ ] Verify an encrypted source digest is unchanged after inspect, recovery, and failed export operations.
- [ ] Confirm `git diff --check`, clean status, app bundle location, signing status, and documented limitations.
- [ ] Commit any verification fixes with `git commit -m "test: verify XLSX Rescue macOS app"`.

## Final Verification Checklist

- [ ] Existing 32 package tests remain green.
- [ ] App model, state, adapter, and presentation tests pass.
- [ ] Visible verifier validates without appearing in logs.
- [ ] Password remains masked until Reveal and is copied only explicitly.
- [ ] Progress shows bounded percentage, tested count, speed, elapsed, ETA, backend, and thermal state.
- [ ] Pause/resume starts from the next untested candidate.
- [ ] Cancel/reset clear active tasks and password presentation.
- [ ] Source workbook remains byte-for-byte unchanged.
- [ ] Unsigned clean build succeeds.
- [ ] Development-signed build succeeds when the configured identity is available.
- [ ] Deliverable `.app` launches from `outputs/`.
