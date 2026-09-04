# Contributing

Thanks for helping make Refill more reliable. Small, focused changes are easiest to review.

## Set up

You need macOS 13 or newer and Apple's Command Line Tools:

```sh
xcode-select --install
git clone https://github.com/10-01/Refill.git
cd Refill
make check
```

Run `make install` to test the app from `~/Applications/Refill.app`.

## Before a pull request

- Run `make check`.
- Add sanitized parser fixtures when a provider response format changes.
- Test account isolation if you change environment or home-path handling.
- Include light and dark screenshots for visible UI changes.
- Update the README or architecture notes when public behavior changes.
- Keep provider calls off the main thread and preserve stale data on transient failures.

Never commit real tokens, `auth.json`, Keychain exports, provider home directories, raw terminal captures, or account-specific cache files. Replace names, IDs, timestamps, and quota values in fixtures.

## Design changes

The UI follows Otis. Read the linked design system before changing layout, type, color, or interaction patterns. Keep the popover compact and native. Ink is the default meter fill; orange is the alarm when a window is low. Verify both macOS appearances.

## Provider changes

Each provider adapter should return the common `ProviderUsage` model and a short actionable error. Do not add a hosted proxy or send credentials anywhere except the account's provider. Document any unofficial or fragile interface in `ARCHITECTURE.md`.

## Commit and pull request scope

Use an imperative commit subject and explain the user impact in the pull request. Separate provider behavior, UI work, and broad refactors when they can be reviewed independently.
