# Open-source readiness review

Review date: 2026-09-02

## Decision

The source repository is public and ready for contributors. A downloadable binary release is not ready until it is signed with a Developer ID certificate and notarized by Apple.

## Ready

- MIT license and third-party notices are present.
- Geist's complete SIL Open Font License is bundled with source and app output.
- README covers requirements, installation, privacy, provider behavior, updates, development, and distribution.
- Contribution, security, architecture, changelog, issue, and pull request guidance are present.
- CI builds, tests, packages, and verifies the macOS deployment target and universal architectures.
- GitHub Actions uses a full commit SHA and Dependabot is configured for action updates.
- The app has no analytics, backend, package dependencies, or copied credential store.
- Local metadata and exports use owner-only permissions.
- Native and universal builds are reproducible from the included scripts.
- Repository screenshots and the social preview regenerate from native proof views with `make media`.

## Published repository

- The public repository is `10-01/Refill`.
- The repository has a description, relevant topics, and a generated social preview.
- GitHub Actions runs the full build, test, package, and verification path on macOS.
- The tracked history and fixtures contain no provider credentials.

## Before publishing a binary release

- Obtain or select a Developer ID Application certificate.
- Store `notarytool` credentials in a dedicated Keychain profile.
- Run the documented signed and notarized `make package` command.
- Confirm `spctl --assess --type execute --verbose=4 Refill.app` accepts the stapled build on a clean Mac.
- Publish the ZIP and its SHA-256 file from `dist/` as matching release assets.
- Test first launch, Keychain prompts, Terminal automation, launch at login, and all three providers from the downloaded artifact.

## Known maintenance risks

- Claude's OAuth usage route and beta header are provider-controlled and may change.
- Codex depends on a local app-server JSON-RPC method that may change.
- Grok depends on an English terminal UI and is the least stable integration.
- Credential-free CI can test parsers and builds, but not live provider sessions.
- The test suite is focused on parsing, account identity, and authentication routing; broader model and UI automation would improve regression coverage.

## Optional follow-ups

- Add a contributor code of conduct if the repository develops a community.
- Add a Homebrew cask only after a stable, notarized release URL exists.
- Add a tag-triggered release workflow after signing secrets and release ownership are settled.
