# Architecture

Refill is a small AppKit and SwiftUI menu-bar app compiled directly with `swiftc`. It has no package dependencies or application backend.

## Data flow

1. `AccountStore` discovers T3 and default CLI homes, then saves display metadata in `accounts.json`.
2. `RefillModel` schedules provider reads on a utility `OperationQueue` capped at three concurrent operations.
3. `ProviderClient` adapts each provider into `ProviderUsage`.
4. Successful values are cached in `UserDefaults`. A failed refresh keeps the last value and marks it stale.
5. The UI receives one state update on the main queue and writes an owner-readable `refill.json` snapshot.

The concurrency cap prevents a large account list from launching an unbounded number of CLI processes. No background thread is held solely to wait for the full refresh group.

## Provider adapters

### Claude

Refill asks the Claude CLI whether each home is signed in, reads its OAuth credential from the corresponding macOS Keychain item, and makes a short-lived HTTPS request to Anthropic's usage endpoint. It prefers the endpoint's `limits` array, where `session`, `weekly_all`, and `weekly_scoped` entries become separate rows. A scoped model such as Fable therefore contributes to the tightest-limit menu-bar value. Older flat session, weekly, Fable, Sonnet, and Opus fields remain supported as a fallback. The endpoint and beta header may change with Claude Code.

### Codex

Refill starts one local `codex app-server --stdio` process per account, completes its JSON-RPC initialization, and calls `account/rateLimits/read`. Each process is terminated after the response or a 15-second timeout.

### Grok

The Grok CLI does not expose an equivalent machine-readable command. Refill runs its terminal UI in a pseudo-terminal, answers the cursor-position query, requests `/usage`, strips ANSI control sequences, and parses the English weekly-limit view. It reads used quota from the summary or dialog and ignores the startup warning such as `Weekly limit left: 0%`, which reports remaining quota. When the terminal repaints, the latest usage value and its following reset line win. Grok's reset text is a local wall-clock time. A single cancelable timer handles startup retries and a short fallback when the reset line is absent. This is the most fragile adapter and should be tested against each supported Grok CLI update.

### Muse

Refill reads the Muse Code OAuth token for each home. On macOS the default login keeps that token in the Keychain item `ai.meta.dev.credentials` / `meta`, which `~/.config/muse/auth.json` points at with `storage: "keychain"`. An `access_token` written into a home's `auth.json` is used instead when present. Refill then sends the same request Muse Code sends at startup, `POST https://api.meta.ai/muse-code/key` with `{"onboard": false}` and `x-api-version: 1.0.0`. The `subs_usage.window` and `subs_usage.weekly` objects become the five-hour and weekly rows. The response also returns an API key. Refill drops that field before it builds the quota model and does not store it. The endpoint is rate-limited, so a 429 keeps the previous reading and marks it stale.

## Refresh policy

Refill refreshes on launch, every five minutes with timer tolerance, on wake, and when an older popover is opened. Repeated requests during an active refresh collapse into one follow-up refresh. The UI never waits synchronously for network or CLI work.

## Local files

`~/Library/Application Support/Refill/` contains:

- `accounts.json`: provider, display name, source, and optional isolated home path
- `refill.json`: current sanitized usage snapshot
- `Providers/`: homes created when the user chooses an isolated login

The registry and export use mode `0600`; created directories use mode `0700`. Authentication files remain owned by their provider CLI.

## Build and release

`build.sh` creates the app bundle, targets macOS 13, registers bundled Geist fonts, generates the icon, enables hardened runtime, and signs the bundle. Local builds use an ad hoc identity. `Scripts/package.sh` creates a universal ZIP and can sign and notarize it when release credentials are supplied through environment variables.
