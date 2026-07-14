# AirStrings iOS SDK

Swift Package that fetches, verifies, caches, and exposes Ed25519-signed localized string bundles. SwiftUI-first via `@Observable` and `@Environment(\.airStrings)`.

**Platform:** iOS 17+ / macOS 14+ | **Swift:** 6.0 (strict concurrency) | **Dependency:** SmartNet (networking only)

## Code Style

- **Indentation:** 2 spaces (tab width: 2, indent width: 2). No tabs.

## Non-Negotiables

Inherited from the parent project — these override everything else:

1. **Bundles are always signed.** No unsigned delivery path. Verification failure = hard error. Never display unverified strings.
2. **Signature verification order matters.** key_id lookup → canonical JSON → Ed25519 verify → format_version check. Do not reorder.
3. **Re-verify on cache load.** Defense in depth — cached bundles are re-verified every time they're loaded from disk.
4. **Anti-downgrade.** Never replace a higher-revision bundle with a lower one for the same locale.
5. **Never crash, never block.** Network errors are silent. Signature failures reject the bundle but keep cached data. No cache + no network = key names as fallback.
6. **No secrets in source.** Public keys are provided by the integrator at init. Never hardcode, log, or embed keys.
7. **Tests accompany every deliverable.** No merge without tests covering the new behavior.

## Security Rules

Hard constraints. Violating any of them is a security bug.

- **Canonical JSON must be byte-identical across platforms.** Keys sorted lexicographically at every level. No whitespace. Integers as integers. RFC 8259 string escaping only. Any change requires updating `docs/contracts/bundle-format.md` and testing against the backend's output.
- **Signature covers metadata.** format_version, project_id, locale, revision, created_at are all in the signed content.
- **Unknown key_id = reject entirely.** Do not fall back to trying other keys.
- **Unknown format_version = reject entirely.** Even if the signature is valid.
- **Base64url signatures must decode to exactly 64 bytes.** Reject anything else.
- **Cache is untrusted storage.** Always re-verify after loading from disk. If verification fails, delete the cache and fetch fresh.

## SmartNet Gotchas

SmartNet is isolated to `Networking/BundleFetcher.swift`. No other file imports SmartNet.

- **Closure API required for ETag.** SmartNet's async/await API discards response headers. Use `request(with:completion:)` wrapped in `withCheckedThrowingContinuation`.
- **304 is an error in SmartNet.** Non-2xx = `NetworkError.error(statusCode:data:)`. Intercept 304 via `response.statusCode` before checking `response.result`.
- **Debug logging off.** `NetworkConfiguration(debug: false)` — SmartNet prints cURL by default.
- **Module name collision.** The module is `SmartNet`, the client class is `ApiClient`. Do not use `SmartNet` as a type name.

## Patterns to Avoid

- **Don't add Combine.** Observation framework is sufficient for iOS 17+.
- **Don't add Objective-C compatibility.**
- **Don't add protocol abstractions preemptively.** No `BundleFetchable`, `BundleVerifiable`, etc. until there's a second implementation.
- **Don't cache in memory beyond the strings dict.** `strings` on `AirStrings` is the single source of truth.
- **Don't use JSONEncoder for canonical JSON.** `JSONEncoder` does not guarantee key ordering or compact formatting.
- **Don't add SwiftUI view modifiers or custom views.** The SDK exposes data, not UI.
- **Don't retry on signature failure.** The bundle is rejected. Retrying the same CDN edge will return the same bytes.
- **Don't log secrets, keys, or signature bytes.** Log key_id, revision, locale only.

## v1 Scope Boundaries

**In v1:** Fetch, verify, cache, serve strings. One locale at a time. Foreground refresh. ETag-based conditional requests. Key rotation via multiple configured public keys.

**Not in v1 (do not build):** Analytics/telemetry, background app refresh, push-triggered updates, multiple simultaneous locales, Combine publishers, SwiftUI preview helpers, server-driven locale negotiation.

## ICU MessageFormat Support

Strings have a `format` field: `"text"` (plain) or `"icu"` (ICU MessageFormat). Bundle values are objects, not bare strings:

```json
{ "welcome": { "value": "Welcome!", "format": "text" } }
```

### API contract

- `subscript[key]` and `strings` dictionary: return the **raw value** (preserves backward compatibility).
- `func string(_ key: String, args: [String: Any]) -> String`: formats ICU patterns via Foundation, returns value as-is for text, falls back to raw pattern on failure.

### Canonical JSON

Each string serializes as `{"format":..., "value":...}` (keys sorted lexicographically).
