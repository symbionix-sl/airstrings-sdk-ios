# AirStrings iOS SDK

Swift Package that fetches, verifies, caches, and exposes Ed25519-signed localized string bundles. SwiftUI-first via `@Observable` and `@Environment(\.airStrings)`.

**Platform:** iOS 17+ / macOS 14+ | **Swift:** 6.0 (strict concurrency) | **Dependency:** SmartNet (networking only)

## Non-Negotiables

Inherited from the parent project — these override everything else:

1. **Bundles are always signed.** No unsigned delivery path. Verification failure = hard error. Never display unverified strings.
2. **Signature verification order matters.** key_id lookup → canonical JSON → Ed25519 verify → format_version check. Do not reorder.
3. **Re-verify on cache load.** Defense in depth — cached bundles are re-verified every time they're loaded from disk.
4. **Anti-downgrade.** Never replace a higher-revision bundle with a lower one for the same locale.
5. **Never crash, never block.** Network errors are silent. Signature failures reject the bundle but keep cached data. No cache + no network = key names as fallback.
6. **No secrets in source.** Public keys are provided by the integrator at init. Never hardcode, log, or embed keys.
7. **Tests accompany every deliverable.** No merge without tests covering the new behavior.

## Architecture

```
Sources/AirStrings/
├── AirStrings.swift              # @Observable public API — the only public class
├── AirStringsConfiguration.swift # Init config (projectId, publicKeys, locale, baseURL)
├── AirStringsLocale.swift        # .system | .fixed("en-US")
├── AirStringsError.swift         # Public error enum
├── Models/
│   ├── StringBundle.swift        # Codable bundle envelope (internal)
│   └── CanonicalJSON.swift       # Deterministic serializer for signature verification
├── Networking/
│   └── BundleFetcher.swift       # SmartNet wrapper with ETag/304 support
├── Security/
│   ├── BundleVerifier.swift      # Ed25519 verification via CryptoKit
│   └── Base64URL.swift           # RFC 4648 §5 codec
├── Storage/
│   └── BundleStore.swift         # Disk cache in Library/Caches/AirStrings/
└── Extensions/
    └── EnvironmentValues+AirStrings.swift  # @Environment(\.airStrings)
```

### Layer Rules

| Layer | May depend on | Never depends on |
|-------|---------------|-------------------|
| `Models/` | Foundation only | Networking, Storage, Security |
| `Security/` | Models, Foundation, CryptoKit | Networking, Storage |
| `Networking/` | Foundation, SmartNet | Security, Storage, Models |
| `Storage/` | Foundation | Security, Networking, Models |
| `AirStrings.swift` | All internal layers | Nothing depends on it |

SmartNet is isolated to `Networking/BundleFetcher.swift`. No other file imports SmartNet.

### Data Flow

```
CDN → BundleFetcher (raw Data) → JSONDecoder (StringBundle) → BundleVerifier → BundleStore (save) → AirStrings.strings (observable dict)
```

Every step is a distinct responsibility. Data flows in one direction. The `AirStrings` class orchestrates but delegates all work.

## Security Rules

These are hard constraints. Violating any of them is a security bug.

- **Canonical JSON must be byte-identical across platforms.** The serializer in `CanonicalJSON.swift` is the source of truth. Keys sorted lexicographically at every level. No whitespace. Integers as integers. RFC 8259 string escaping only. Any change requires updating the contract in `docs/contracts/bundle-format.md` and testing against the backend's output.
- **Signature covers metadata.** format_version, project_id, locale, revision, created_at are all in the signed content. This prevents bundle substitution, locale swaps, and downgrade attacks.
- **Unknown key_id = reject entirely.** Do not fall back to trying other keys.
- **Unknown format_version = reject entirely.** Even if the signature is valid.
- **Base64url signatures must decode to exactly 64 bytes.** Reject anything else.
- **Cache is untrusted storage.** Always re-verify after loading from disk. If verification fails, delete the cache and fetch fresh.

## Concurrency Model

- `AirStrings` is `@Observable` + `@unchecked Sendable`. The `@unchecked` is justified because all observed property mutations happen from the same call sites (init, refresh, setLocale) and the SDK is designed for single-owner use from SwiftUI (MainActor context).
- `@ObservationIgnored` on all non-UI internal state to prevent unnecessary view invalidations.
- `BundleFetcher` is `@unchecked Sendable` because `ApiClient` (SmartNet) is not formally Sendable but is thread-safe internally (wraps URLSession).
- `BundleVerifier` and `BundleStore` are `Sendable` (all stored properties are `let` + Sendable types).
- Foreground observation uses `NotificationCenter` with `queue: .main`, guarded by `#if canImport(UIKit)`.
- The background refresh `Task` in `init` captures `[weak self]` to avoid retain cycles.

## SmartNet Integration

SmartNet is the sole third-party dependency. Key constraints:

- **Closure API required for ETag.** SmartNet's async/await API discards response headers. We use the closure-based `request(with:completion:)` wrapped in `withCheckedThrowingContinuation` to access `Response.statusCode` and `HTTPURLResponse` headers.
- **304 is an error in SmartNet.** Non-2xx status codes produce `NetworkError.error(statusCode:data:)`. We intercept 304 via `response.statusCode` before checking `response.result`.
- **Debug logging off.** `NetworkConfiguration(debug: false)` — SmartNet prints cURL by default.
- **Module name collision.** The module is `SmartNet`, the client class is `ApiClient`. Do not use `SmartNet` as a type name.

## Testing Standards

### What to test

- **CanonicalJSON:** Byte-exact output against the contract example in `docs/contracts/bundle-format.md`. Key sorting, no whitespace, integer format, string escaping, control character escaping, empty strings object.
- **BundleVerifier:** Valid signature passes. Wrong key fails. Unknown key_id fails. Unsupported format_version fails. Invalid base64url fails. Tampered strings fail. Test with real CryptoKit keypairs — no mocking crypto.
- **BundleStore:** Save/load round-trip. Nil etag. Per-locale isolation. Overwrite. Delete. Corrupted metadata degrades gracefully (returns data with nil etag).
- **Base64URL:** Encode/decode round-trip. URL-safe characters. Missing padding. 64-byte signatures produce exactly 86 chars.
- **AirStrings:** Subscript fallback. Subscript with loaded strings. Initial state. Locale resolution. Placeholder behavior.

### How to test

- Use `@testable import AirStrings` to access internal types.
- `BundleStore` takes an optional `baseDirectory` for test isolation — pass a temp directory.
- For `BundleVerifier`, generate real Ed25519 keypairs with `Curve25519.Signing.PrivateKey()` and sign real canonical JSON. Never mock the crypto.
- `AirStrings` init fires a background `Task { refresh() }` that will fail silently in tests (no server). This is fine — test synchronous state directly.
- Build: `swift build` from `sdks/ios/`.
- Test: `swift test` from `sdks/ios/`.

## Patterns to Follow

- **Public API surface is minimal.** Only `AirStrings`, `AirStringsConfiguration`, `AirStringsLocale`, `AirStringsError`, and the `EnvironmentValues` extension are public. Everything else is internal.
- **Enums for stateless utilities.** `CanonicalJSON`, `Base64URL` are caseless enums (uninhabitable — cannot be instantiated).
- **Structs for stateless services.** `BundleVerifier` is a struct with `let` properties.
- **Final classes for stateful services.** `BundleFetcher`, `BundleStore`, `AirStrings`.
- **No protocol abstractions for v1.** Concrete types everywhere. Protocol extraction happens when we need test doubles or multiple implementations.
- **Errors are Sendable.** `AirStringsError` uses `String` for wrapped context instead of `any Error` to maintain Sendable conformance.
- **Logging via `os.Logger`.** Subsystem: `com.airstrings.sdk`. One logger per component with a descriptive category.

## Patterns to Avoid

- **Don't add Combine.** Observation framework is sufficient for iOS 17+.
- **Don't add Objective-C compatibility.**
- **Don't add protocol abstractions preemptively.** No `BundleFetchable`, `BundleVerifiable`, etc. until there's a second implementation.
- **Don't cache in memory beyond the strings dict.** The `strings` property on `AirStrings` is the single source of truth.
- **Don't use JSONEncoder for canonical JSON.** `JSONEncoder` does not guarantee key ordering or compact formatting. The hand-rolled serializer in `CanonicalJSON.swift` exists for a reason.
- **Don't add SwiftUI view modifiers or custom views.** The SDK exposes data, not UI. Views are the app's responsibility.
- **Don't retry on signature failure.** If verification fails, the bundle is rejected. Retrying the same CDN edge will return the same bytes.
- **Don't log secrets, keys, or signature bytes.** Log key_id (identifier), revision, locale — never raw key material or signature data.

## v1 Scope Boundaries

**In v1:** Fetch, verify, cache, serve strings. One locale active at a time. Foreground refresh. ETag-based conditional requests. Key rotation via multiple configured public keys.

**Not in v1 (do not build):** Analytics/telemetry, ICU MessageFormat, plural handling, background app refresh, push-triggered updates, multiple simultaneous locales, Combine publishers, SwiftUI preview helpers, server-driven locale negotiation.
