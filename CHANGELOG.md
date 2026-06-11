# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-10

### Added

- Bundled fallback (seed): on startup and on `setLocale(_:)`, the SDK probes the app bundle for committed, signed bundles at `{locale}.json` under the `airstrings/bundles` seed directory and serves them on cold starts with no cache and no network. See the [bundled fallback contract](https://github.com/symbionix-sl/airstrings/blob/main/docs/contracts/bundled-fallback.md).
- `AirStringsConfiguration.seedBundle` (default `.main`), `seedSubdirectory` (default `"airstrings/bundles"`), and `isSeedingEnabled` (default `true`) — additive configuration; existing integrations compile and run unchanged.
- `AirStringsError.seedProjectMismatch` and `AirStringsError.seedLocaleMismatch` surfaced when a seed bundle fails the project ID or locale cross-check.

### Security

- Seed files are untrusted input: every seed runs the full Ed25519 verification pipeline plus `project_id` and locale cross-checks. Invalid, tampered, or mismatched seeds are never applied, never cached, and are logged at error level; the SDK continues unaffected.
- Anti-downgrade extends to seeding: the highest verified revision among cache and seed wins, ties prefer the cache, a winning seed is persisted through the normal cache path, and network refresh keeps its existing anti-downgrade check.
