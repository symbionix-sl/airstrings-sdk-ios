# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-14

### Added

- String Variants (experiments) support. Assign a stable variant per user and forward exposure events to your own analytics — additive and opt-in; existing integrations compile and run unchanged.
- `AirStrings.setAssignmentId(_ id: String?)` — sets the stable per-user assignment identifier used for variant selection. Selection is stateless and deterministic: the same assignment ID and experiment always resolve to the same variant. Pass `nil` to clear the assignment and serve base values.
- `AirStrings.onExposure: ((ExposureEvent) -> Void)?` — callback fired when a variant value is served, so the app can forward exposures to its own analytics pipeline. The SDK ships no telemetry of its own.
- `ExposureEvent` — value type describing a served variant: `key`, `experimentId`, `variant`, `locale`, and `assignmentId` (all `String`).
- Signed experiments verification: experiment assignments run the same Ed25519 verification pipeline as string bundles and soft-fail to base values when verification does not pass — a failed or absent experiment never blocks strings and never serves an unverified variant.

## [1.0.0] - 2026-07-13

First stable release. The public API is now frozen under Semantic Versioning: no breaking change ships without a major (2.0.0) bump. See the SDK stability and deprecation policy in `docs/contracts/sdk-requirements.md`.

### Changed

- Promoted to 1.0.0. No functional changes from 0.4.1 — this release marks the public API surface as stable.

## [0.4.1] - 2026-06-23

### Changed

- Raised the SmartNet dependency floor from `2.0.1` to `2.2.0`. Verified the SDK builds and all tests pass against SmartNet 2.2.0. This aligns the SDK with consumers that pin SmartNet `2.2.0` and avoids duplicate-SmartNet link failures in environments that resolve dependency graphs in isolation (e.g. Bazel).

## [0.4.0] - 2026-06-11

### Changed

- **BREAKING:** Removed the `AirStrings` singleton. The integrating app now constructs and owns the instance via `AirStrings(configuration:)` and injects it into SwiftUI with `.environment(\.airStrings, instance)`. This aligns the iOS SDK with the Android and Web SDKs, which have no singleton.

### Removed

- **BREAKING:** `AirStrings.shared` static property and `AirStrings.configure(_:)` static method. Replace `AirStrings.configure(.init(...))` + `AirStrings.shared` with a single owned instance: `let airStrings = AirStrings(configuration: .init(...))`, injected via `.environment(\.airStrings, airStrings)`.

## [0.3.0] - 2026-06-10

### Added

- Bundled fallback (seed): on startup and on `setLocale(_:)`, the SDK probes the app bundle for committed, signed bundles at `{locale}.json` under the `airstrings/bundles` seed directory and serves them on cold starts with no cache and no network. See the [bundled fallback contract](https://github.com/symbionix-sl/airstrings/blob/main/docs/contracts/bundled-fallback.md).
- `AirStringsConfiguration.seedBundle` (default `.main`), `seedSubdirectory` (default `"airstrings/bundles"`), and `isSeedingEnabled` (default `true`) — additive configuration; existing integrations compile and run unchanged.
- `AirStringsError.seedProjectMismatch` and `AirStringsError.seedLocaleMismatch` surfaced when a seed bundle fails the project ID or locale cross-check.

### Security

- Seed files are untrusted input: every seed runs the full Ed25519 verification pipeline plus `project_id` and locale cross-checks. Invalid, tampered, or mismatched seeds are never applied, never cached, and are logged at error level; the SDK continues unaffected.
- Anti-downgrade extends to seeding: the highest verified revision among cache and seed wins, ties prefer the cache, a winning seed is persisted through the normal cache path, and network refresh keeps its existing anti-downgrade check.
