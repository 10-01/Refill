# Security policy

## Supported versions

Security fixes are made against the latest release on the default branch.

## Report a vulnerability

Do not open a public issue for a credential leak, authentication bypass, unsafe command construction, or local data exposure. Use GitHub's private vulnerability reporting for this repository.

Include the affected version, impact, and a minimal reproduction. Do not send real provider credentials. You can expect an acknowledgement within seven days.

## Security boundaries

Refill reads credentials already managed by provider CLIs and macOS Keychain. It does not maintain a hosted account service. Local registry and export files are owner-readable only, but quota values and account display names are still private data and should be handled accordingly.

Provider CLIs and remote provider services remain outside Refill's security boundary. Report a provider vulnerability to that provider directly.
