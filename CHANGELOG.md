# Changelog

## 0.4.0

- Native Qt Quick Shapes logo fixes blank bar rendering; checked in both bar orientations while locked/unlocked.

- Native DMS clipboard with sensitive MIME hint, repeated paste and expiry/lock cleanup; no runtime wl-clipboard dependency.
- Fully bundled backend and dependency licenses; fresh clones only require Node.js 20+ and DMS 1.6.2+.
- Startup dependency check, literal English translation call sites and complete German catalog.
- English/German documentation and sample screenshots, prepared registry metadata and GitHub Actions checks.

## 0.3.0

- Rename the displayed plugin to DankAuth while preserving the enteAuth ID and existing vault/settings.
- Original vector logo inspired by Ente Auth's rounded e and shield, colored through the DMS theme.

## 0.2.0–0.2.1

- Stable cards during OTP updates, inline copy confirmation and optional popout close.
- Sync state, keyboard navigation, encrypted pin/tag writes and adaptive popout height.
- Temporary fingerprint icon, superseded in 0.3.0.

## 0.1.0–0.1.1

- Initial native Ente Auth integration, encrypted local cache, offline unlock, SRP/email/2FA/passkey flows and DMS theme support.
- Clipboard fix for repeated pastes when clipboard observers consume the first request.
