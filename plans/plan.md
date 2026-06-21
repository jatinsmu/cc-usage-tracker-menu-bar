# Claude Code Usage — macOS Menu Bar App

## Context

You repeatedly open the Claude desktop app's usage page and click refresh to see how
much of your Claude Code limit you've used. This app puts that number in the menu bar
and keeps it fresh automatically. It's a greenfield, open-source macOS app (empty repo
at `/Users/jatin/PycharmProjects/cc-usage-tracker-menu-bar`).

**Feasibility is proven (live-tested in this session):**

- **Live quota** comes from `GET https://api.anthropic.com/api/oauth/usage` with headers
  `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. It returns the
  exact desktop-page data:
  ```json
  {"five_hour":{"utilization":23.0,"resets_at":"2026-06-21T17:10:00+00:00", ...},
   "seven_day":{"utilization":11.0,"resets_at":"2026-06-23T15:00:00+00:00", ...},
   "limits":[{"kind":"session","group":"session","percent":23,"severity":"normal","resets_at":...,"is_active":true},
             {"kind":"weekly_all","group":"weekly","percent":11,"severity":"normal", ...}],
   "spend":{"used":{"amount_minor":0,"currency":"USD"},"limit":null,"enabled":false}}
  ```
  (`*_dollars` / `spend` are null on a Pro subscription — see Adaptive display below.)
- **Token** lives in the macOS Keychain, generic password, service `"Claude Code-credentials"`.
  Shape: `{"claudeAiOauth":{"accessToken","refreshToken","expiresAt"(ms),"subscriptionType","rateLimitTier"}}`.
  Claude Code refreshes it automatically while in use.
- **Per-day tokens/cost** come from per-message `usage` blocks in `~/.claude/projects/**/*.jsonl`
  (184 files here). Each assistant line has `message.model` and `message.usage`
  (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`)
  plus a top-level `timestamp`.

## Decisions (confirmed with user)

- **Stack:** Native Swift — SwiftUI `MenuBarExtra` + Swift Charts. No runtime to install.
- **Menu bar shows:** adaptive (see Adaptive display) — 5-hour window `%` for limit-based
  plans (Free/Pro/Max), or dollars spent for usage-billed/enterprise plans; gauge icon, color by severity.
- **History:** BOTH — (a) quota-% snapshots charted over time, and (b) per-day tokens + estimated $ from logs.
- **Codex:** out of scope for v1; design leaves room (see Provider note).

## Architecture

A SwiftPM executable target (`swift build`able, no Xcode needed) assembled into a
`.app` bundle with `LSUIElement=true` (menu-bar agent, no Dock icon). Un-sandboxed,
distributed via GitHub Releases / Homebrew cask (not Mac App Store) so it can read
`~/.claude` and the Keychain.

**Deployment target: macOS 14 (Sonoma) minimum** — `MenuBarExtra`, Swift Charts, and
`SMAppService` are all macOS 13+, with some niceties 14+. Set this explicitly in
`Package.swift` (`platforms: [.macOS(.v14)]`) and document it in the README.

```
cc-usage-tracker-menu-bar/
  Package.swift
  Sources/CCUsageBar/
    CCUsageBarApp.swift      # @main App, MenuBarExtra(label + popover)
    KeychainReader.swift     # read "Claude Code-credentials" -> token + expiresAt
    UsageClient.swift        # async GET /api/oauth/usage -> UsageSnapshot (Codable)
    Models.swift             # UsageSnapshot, Window, Limit, Spend, Severity, DisplayMode
    LogParser.swift          # scan ~/.claude/projects/**/*.jsonl -> per-day aggregates (incremental)
    PricingTable.swift       # model id -> $/Mtok (input/output/cache); est. cost only
    HistoryStore.swift       # persist snapshots + daily aggregates to Application Support
    UsageViewModel.swift     # @MainActor ObservableObject: 60s timer drives poll+parse, publishes state
    Views/
      PopoverView.swift      # 5h bar, 7d bar / spend, reset times, chart, daily table, footer
      QuotaBar.swift         # labeled progress bar, severity color
      HistoryChartView.swift # Swift Charts line: utilization or $ over time
      DailyTableView.swift   # per-day tokens + $ (exact or estimated)
  Resources/Info.plist       # LSUIElement=true, bundle id, version
  scripts/build-app.sh       # assemble Sources build into CCUsageBar.app
  README.md  LICENSE(MIT)
```

### Data flow
1. `UsageViewModel` fires every ~60s (configurable).
2. `KeychainReader` reads the token via the **Security framework directly**
   (`SecItemCopyMatching`), parses the JSON. (See Keychain access note — the `security`
   CLI is kept only as a documented manual fallback.)
3. `UsageClient` GETs `/api/oauth/usage` → decodes `UsageSnapshot`.
4. `LogParser` updates per-day aggregates from JSONL changed since last run (track file
   mtime + byte offset to avoid full reparse).
5. `HistoryStore` appends the quota snapshot and upserts today's aggregate; retention capped (e.g. 14 days).
6. View model publishes; `MenuBarExtra` label updates, popover redraws.

### Adaptive display (plan-aware, data-driven)
Different Claude plans expose usage differently, so the app **chooses its display from the
response**, never from a hardcoded plan list:
- **Limit-based plans (Free / Pro / Max):** `*_dollars` null and `spend.enabled=false`.
  → Show 5h/7d **utilization %**. Bar label = `"<gauge> 23%"`.
- **Usage-billed / enterprise plans:** `spend.enabled=true` and/or `limit_dollars`/
  `used_dollars` populated, plus `extra_usage`/overage fields. There are no hourly limits,
  so → show **dollars**: bar label = `"$12.40"` (used this period), popover shows
  used vs `spend.limit` (% + severity), overage status, and reset/period info.
- **Decision rule:** `if spend.enabled || window.limit_dollars != nil → dollar mode, else → percent mode.`
  Cross-check with Keychain `subscriptionType` / `rateLimitTier` only as a tiebreaker/label.
- `UsageSnapshot` decodes all fields; a computed `displayMode` enum drives both the bar
  label and which popover sections render. The history chart/table switch units to match
  ($ over time for dollar mode, % over time for percent mode); the JSONL per-day table
  stays useful in both (tokens always; $ exact in dollar mode, estimated in percent mode).

### Menu bar label
`MenuBarExtra` with a `Label` — gauge SF Symbol + `Text` of either `"\(fiveHour)%"` or
`"$\(spent)"` per `displayMode`. **Severity is conveyed by the glyph, not text color:**
macOS generally renders menu-bar labels as monochrome template content and ignores custom
foreground colors, so swap the symbol by severity (e.g. `gauge.with.dots.needle.33percent`
→ `...67percent` → `exclamationmark.triangle.fill`, or an `gauge` + badge). Full-color
severity lives in the popover, which has no such restriction. **Verify color/glyph
rendering in build step 1** in both light and dark menu bar appearances before relying on
it. Popover content from `PopoverView`.

## Key implementation notes

- **Keychain access (the #1 risk — de-risk in build step 2):** the Keychain ACL is keyed
  to the *requesting binary's code signature*. Two pitfalls behind the naive "one prompt,
  Always Allow once" story:
  - Shelling to `/usr/bin/security` whitelists Apple's `security` binary (not your app),
    and the CLI is known to re-prompt unreliably / not persist the ACL across some macOS
    versions.
  - An unsigned or per-build **ad-hoc** signature changes identity every build, so
    "Always Allow" never sticks.
  → Read via the **Security framework** (`SecItemCopyMatching`) and sign the app with a
  **stable self-signed identity** so the ACL persists. Expect one macOS "wants to use
  confidential information" prompt → Always Allow once. **Test ACL persistence across a
  rebuild + relaunch (no new prompt) before building anything on top of it.** Document the
  prompt in the README; keep the `security` CLI as a manual fallback only.
- **Token expiry / degradation:** if `expiresAt` is past or the GET returns 401, show a
  gentle "Sign-in expired — open Claude Code to refresh" state and keep showing last-good
  values dimmed. (Stretch: implement OAuth refresh with the stored `refreshToken` against
  the standard token endpoint so the app works even when Claude Code hasn't run recently.)
- **Undocumented endpoint fragility:** `/api/oauth/usage` + the `oauth-2025-04-20` beta
  header is an internal endpoint that can change without notice. On parse/HTTP failure,
  degrade gracefully (see offline/expired states); the JSONL-derived per-day history keeps
  working even if the endpoint breaks, so it's the resilient data path.
- **Offline:** keep last snapshot, dim the label, retry next tick.
- **No Keychain entry / never signed in:** onboarding message in the popover.
- **Cost figures:** in **dollar mode** use the API's real charged dollars (exact). In
  **percent mode** (Pro/Max flat-fee, API returns null dollars), the per-day `$` is an
  *estimated API-equivalent* cost = tokens × bundled `PricingTable`, labeled as an estimate.
  At implementation time, pull exact current model prices via the `claude-api` skill rather
  than hardcoding guesses (handle `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5`,
  `claude-fable-5`, and cache-read/write tiers).
- **JSONL incremental parse:** track file mtime + byte offset, but handle the two cases
  that break naive offset tracking: a file **truncated/rewritten** (offset > current size
  → reparse from 0) and a **partial last line** (don't commit an incomplete JSON line;
  resume from the last newline next tick).
- **Dollar-mode display is untested on this account:** percent mode is verified on this
  Pro account, but `spend.enabled=true` (usage-billed/enterprise) is inferred. Check in a
  real `spend.enabled=true` JSON **fixture** and unit-test dollar mode against it before
  shipping it.
- **History persistence:** start with a `Codable` JSON file in
  `~/Library/Application Support/CCUsageBar/` (snapshots array + daily map), capped by
  retention. Swap to SQLite only if volume warrants.
- **Provider seam (future Codex):** define a `UsageProvider` protocol
  (`func snapshot() async throws -> UsageSnapshot`) so a `CodexProvider` reading `~/.codex`
  can be added without touching the UI layer.
- **Polling cost:** the endpoint is light; 60s default, expose an interval setting later.
- **Launch at login:** offer a `SMAppService.mainApp` toggle in the popover footer (stretch).

## Build sequence

1. `Package.swift` (macOS 14 target) + minimal `MenuBarExtra` app that shows a static
   label → confirm it appears in the menu bar. `scripts/build-app.sh` owns embedding
   `Info.plist`, setting `LSUIElement`, **and codesigning with the stable self-signed
   identity** (not an afterthought — see Keychain access). Verify the severity glyph/text
   renders as intended in both light and dark menu bars here.
2. `KeychainReader` + `UsageClient` + `Models`; wire `UsageViewModel` 60s poll → live 5h %
   in the bar and a basic popover with 5h/7d bars + reset times.
3. Adaptive display: `displayMode` from the response → dollar mode for usage-billed plans
   (spend used vs limit, overage); percent mode otherwise.
4. Severity coloring + offline/expired/onboarding states.
5. `HistoryStore` snapshotting + `HistoryChartView` (% or $ over time per mode).
6. `LogParser` + `PricingTable` + `DailyTableView` (per-day tokens + $).
7. README (install, the Keychain prompt, screenshots), MIT LICENSE, optional Homebrew cask.

## Verification

- **Live number matches reality:** run the app, compare the bar's value against
  `curl -s https://api.anthropic.com/api/oauth/usage -H "Authorization: Bearer $(security find-generic-password -s 'Claude Code-credentials' -w | python3 -c 'import sys,json;print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')" -H 'anthropic-beta: oauth-2025-04-20'`
  and against the desktop app's usage page.
- **Adaptive display:** verify percent mode on this Pro account; verify dollar mode against
  a usage-billed/enterprise account's response (or a mocked `spend.enabled=true` fixture).
- **Auto-refresh:** leave it running, use Claude Code, confirm the value moves within ~1 poll.
- **History:** let it run across a window reset and over a day; confirm the chart fills and
  the daily table sums tokens. Cross-check daily totals against `ccusage` if installed.
- **Degradation:** disconnect network → label dims, last value retained; revoke/expire
  token → "open Claude Code" state; missing Keychain item → onboarding state.
- **Keychain ACL persistence:** rebuild → relaunch → confirm **no** new Keychain prompt
  appears (proves the Security-framework read + stable signature kept the ACL).
- **Menu-bar severity:** confirm the glyph/text shows the intended severity in both light
  and dark menu bar appearances.
- **Packaging:** `scripts/build-app.sh` produces a launchable, codesigned `CCUsageBar.app`
  with no Dock icon; quit from the popover works.