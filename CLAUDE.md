# CLAUDE.md

Guidance for working in this repo. Read before making changes.

## What this is

CCUsageBar — a macOS menu bar app (SwiftUI `MenuBarExtra`) that shows Claude Code
rate-limit usage. It reads the OAuth token Claude Code stores in the Keychain,
polls `GET https://api.anthropic.com/api/oauth/usage`, and renders the 5-hour and
7-day quota windows in the menu bar plus a popover.

## Build, run, test

- **Build the app (local):** `bash scripts/build-app.sh` then `open CCUsageBar.app`.
  Uses `swiftc` directly so it works on **Command Line Tools-only** machines (no Xcode).
- **CI / no-codesign build:** `CCUSAGEBAR_SKIP_SIGN=1 bash scripts/build-app.sh`.
- **Release:** bump `CFBundleShortVersionString` in `Resources/Info.plist` in its own PR
  and merge it to `main` **before** releasing — `release.yml` checks the tag against this
  value and fails the release if they don't match. Then either push a matching `vX.Y.Z`
  tag, or trigger **Actions → Release → Run workflow** and type the version (it creates
  the tag for you). Either path builds an **ad-hoc-signed** (`CCUSAGEBAR_ADHOC_SIGN=1`)
  zip and publishes it. Local rebuilds still use the stable self-signed identity; ad-hoc
  is the release path only (no Developer ID).
- **Tests:** `swift test` — **requires a full Xcode install** (SwiftPM needs the macOS
  platform SDK that CLT alone doesn't provide). On CLT-only machines you can't run the
  suite locally; CI runs it on every PR.
- The build script resolves the SDK with `xcrun --sdk macosx --show-sdk-path` — never
  hardcode an SDK path (it breaks when Xcode is the active toolchain).

## Architecture — one-way data flow

`KeychainReader → UsageClient → UsageViewModel (@MainActor) → SwiftUI views`

- **`KeychainReader`** — `SecItemCopyMatching` for `"Claude Code-credentials"`.
  `parse(_:)` is pure and unit-tested. Never use the `security` CLI to read the token:
  it would bind the Keychain ACL to Apple's binary instead of ours.
- **`UsageClient`** — async GET. `decode(_:)` / `makeDecoder()` are pure and tested.
  The endpoint + `anthropic-beta: oauth-2025-04-20` header is an **internal Anthropic
  API that can change without notice** — always degrade gracefully, never crash.
- **`UpdateChecker`** — Foundation-only GitHub Releases check. `isNewer(_:than:)` /
  `parseLatest(_:)` are pure and tested. Update state lives on the view model as a
  **separate** `UpdateAvailability` (not an `AppState` case) so it's orthogonal to usage
  and shows in any state. Hybrid by design: downloads the asset and reveals it in Finder
  for manual install — no silent swap (would break Gatekeeper + the Keychain ACL).
- **`UsageViewModel`** — owns `AppState` and the 15-minute poll loop. `init(autoStart:)`
  lets tests build it with no network/Keychain side effects. The Keychain read runs off
  the main actor because the ACL dialog blocks synchronously.
- **Views** — `PopoverView` routes on `AppState`; `QuotaTrackView` is the bar;
  `QuotaMetrics.swift` holds the pure pace math; `Theme.swift` holds the palette.

## Conventions

- Keep pure logic (parsing, decoding, metrics) in I/O-free, SwiftUI-free functions so it
  stays unit-testable — and **add a test when you add such logic**.
- Every new `AppState` case must be handled in three places: `menuBarLabel`,
  `menuBarSymbol`, and `PopoverView.stateContent`.
- **Errors are user-facing.** Write them in the interface's voice and say what to do next
  ("Open Claude Code to sign in again"), never surface a raw status code in the popover.
- **Target is macOS 13.** Don't use 14+ APIs (`.smooth`/`.snappy`, `Observation`, etc.).
  Keep the floor in sync across `Package.swift`, `scripts/build-app.sh`, and the README.
- **No new dependencies** — Foundation, SwiftUI, Security only. Two network endpoints:
  `api.anthropic.com` (usage) and `api.github.com` (the once-a-day update check in
  `UpdateChecker`). Both must degrade gracefully. Never log or persist the token.

## Design standards

The popover is a **native macOS surface with a Claude-derived accent — not a webpage in a
window.** Hold this line:

- Backgrounds and text use **system materials / label colors** (`.secondary`, `.tertiary`)
  so light/dark and vibrancy work for free. Only the *data* accent is branded.
- The accent ramp lives in `Theme.swift`: **coral (normal) → ochre (warning) →
  clay (critical)**. Reuse `Severity.tint`; don't introduce new colors.
- Type is SF Pro. Numbers use `.monospacedDigit()` so they don't jitter on refresh; the
  hero readout is `.rounded`.
- **Hierarchy is information:** the 5-hour window is the hero (it interrupts a session);
  the 7-day window is quiet and secondary.
- The **signature** is the pace marker on the hero track — the hairline showing how far
  through the reset window you are, so "usage ahead of the clock" is visible at a glance.
  Spend the boldness there; keep everything else restrained.
- **Motion:** exactly one micro-interaction (the track fill easing on refresh), gated on
  Reduce Motion. Don't add more — extra animation is what makes UI feel AI-generated.

## Gotchas

- Don't commit build output: `.build/`, `CCUsageBar.app/`, and `.idea/` are gitignored.
- The stable self-signed identity created by `build-app.sh` is what keeps the Keychain
  ACL valid across rebuilds — don't switch to ad-hoc (`-`) signing.
