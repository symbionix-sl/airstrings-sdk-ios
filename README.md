# AirStrings iOS SDK

Fetch, verify, and serve remotely-managed localized strings with Ed25519 signature verification and offline caching.

## Requirements

- iOS 17+ / macOS 14+
- Swift 6.0+
- Xcode 16+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/symbionix-sl/airstrings-sdk-ios.git", from: "0.4.1")
]
```

Or in Xcode: **File > Add Package Dependencies** and enter the repository URL.

## Quick Start

Create an `AirStrings` instance at app launch, own it, and inject it into SwiftUI:

```swift
import AirStrings

let airStrings = AirStrings(configuration: .init(
    organizationId: "org_a1b2c3d4e5f6",
    projectId: "proj_a1b2c3d4e5f6",
    environmentId: "env_a1b2c3d4e5f6",
    publicKeys: ["BASE64_ENCODED_PUBLIC_KEY"]
))
```

Read strings via subscript:

```swift
let title = airStrings["onboarding.welcome_title"]
```

### SwiftUI

Own the instance with `@State` and inject it at the root for `@Environment` access:

```swift
@main
struct MyApp: App {
    @State private var airStrings = AirStrings(configuration: .init(
        organizationId: "org_a1b2c3d4e5f6",
        projectId: "proj_a1b2c3d4e5f6",
        environmentId: "env_a1b2c3d4e5f6",
        publicKeys: ["BASE64_ENCODED_PUBLIC_KEY"]
    ))

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.airStrings, airStrings)
        }
    }
}

struct ContentView: View {
    @Environment(\.airStrings) var strings

    var body: some View {
        Text(strings["onboarding.welcome_title"])
    }
}
```

### ViewModels

Pass the instance into your ViewModel:

```swift
@MainActor
@Observable
final class SettingsViewModel {
    private let strings: AirStrings

    init(strings: AirStrings) {
        self.strings = strings
    }

    var title: String {
        strings["settings.title"]
    }

    var itemCount: String {
        strings.string("items.count", args: ["count": items.count])
    }
}
```

Construct it from a view with the injected instance, e.g. `SettingsViewModel(strings: strings)`.

### String Formatting (ICU MessageFormat)

Strings with `"icu"` format support plurals, selects, and argument substitution:

```swift
// Pattern: "{count, plural, one {# item} other {# items}}"
strings.string("items.count", args: ["count": 3])
// → "3 items"

// Pattern: "{gender, select, male {He} female {She} other {They}}"
strings.string("user.pronoun", args: ["gender": "female"])
// → "She"
```

The `subscript` always returns the raw value. Use `string(_:args:)` when you need formatting.

### Locale

The SDK uses the device locale by default. Override with a fixed locale:

```swift
let airStrings = AirStrings(configuration: .init(
    organizationId: "org_a1b2c3d4e5f6",
    projectId: "proj_a1b2c3d4e5f6",
    environmentId: "env_a1b2c3d4e5f6",
    publicKeys: ["BASE64_ENCODED_PUBLIC_KEY"],
    locale: .fixed("fr")
))
```

Switch locale at runtime:

```swift
await airStrings.setLocale("es")
```

## Bundled fallback (offline-safe builds)

Ship published, signed bundles inside your app so a cold start with no cache and no network serves real strings instead of key names. On startup and on `setLocale(_:)` the SDK seeds from the committed bundled fallback files: every seed runs the full Ed25519 verification pipeline (plus project ID and locale cross-checks), and the highest verified revision among cache and seed wins — ties prefer the cache, and the network refresh continues unchanged in the background.

Two steps:

1. Pull the published bundles into your repo:

   ```sh
   airstrings bundles pull
   ```

2. Commit the generated `airstrings/bundles/` seed directory and add it to your app target.

**CRITICAL packaging note** — the `airstrings/bundles` subdirectory hierarchy must be preserved by the build system:

- **Xcode targets:** add the committed `airstrings/` folder as a **folder reference** (blue folder, not a group)
- **SPM targets:** declare `resources: [.copy("airstrings")]` — never `.process`, which flattens. If the resource is declared in a library or feature target rather than the app target, it lands in that target's `Bundle.module`, not `.main`: pass `seedBundle: .module` (from code inside that module) in the configuration
- **Bazel targets:** use structure-preserving resource rules (e.g. `apple_resource_group` with `structured_resources`)

The SDK does not probe the bundle root — a flattened layout is treated as absent.

Seeding is zero-config when the seed directory is present, and fully optional:

```swift
let airStrings = AirStrings(configuration: .init(
    organizationId: "org_a1b2c3d4e5f6",
    projectId: "proj_a1b2c3d4e5f6",
    environmentId: "env_a1b2c3d4e5f6",
    publicKeys: ["BASE64_ENCODED_PUBLIC_KEY"],
    seedBundle: .main,                      // source bundle to probe (override for app extensions, tests, SPM library targets)
    seedSubdirectory: "airstrings/bundles", // seed directory inside the bundle
    isSeedingEnabled: true                  // set false to disable seeding entirely
))
```

A missing seed directory or locale file is a silent no-op. A tampered, mismatched, or otherwise invalid seed file is a hard error: it is never applied, never cached, and is logged at error level — the SDK then continues with cache, network, or key-name fallback as usual.

A fresh install serves the committed revision until the first successful fetch, so run `airstrings bundles pull` in CI or as a pre-release step to keep seeds current.

Full specification: [bundled fallback contract](https://github.com/symbionix-sl/airstrings/blob/main/docs/contracts/bundled-fallback.md) (`docs/contracts/bundled-fallback.md` in the AirStrings platform repo).

## Reactivity

`AirStrings` is `@Observable`. SwiftUI views that read `strings`, `currentLocale`, `isReady`, or `revision` automatically re-render when those values change — no Combine, no manual subscriptions.

This works transitively through ViewModels: if an `@Observable` ViewModel reads `strings["key"]` from its injected `AirStrings` instance in a computed property, SwiftUI tracks that dependency and re-renders when the strings update.

Strings update automatically on:
- **Init** — loads cache immediately, then fetches from CDN in the background
- **Foreground return** — re-fetches when the app comes back from background
- **`setLocale(_:)`** — loads cached bundle for the new locale, then fetches latest
- **`refresh()`** — manual trigger

All paths are silent on failure — views keep showing the last known strings (or key names as fallback if no bundle has ever loaded).

## How It Works

1. On init, gathers local candidates — the cached bundle and the bundled fallback seed (if present) — verifies each, applies the highest revision, and fetches the latest from CDN
2. Every bundle is Ed25519-signed. Verification is mandatory — invalid signatures are a hard error
3. Verified bundles are cached to `Library/Caches/AirStrings/` for offline use; a winning seed is persisted through the same cache path
4. Cached bundles are re-verified on every load (defense in depth)
5. Auto-refreshes when the app returns to foreground
6. Uses `ETag` / `If-None-Match` to avoid re-downloading unchanged bundles
7. If no bundle is available (no cache + no seed + no network), string keys are returned as fallback

## API

### `AirStrings`

| Member | Type | Description |
|--------|------|-------------|
| `init(configuration:)` | — | Creates an instance; loads cache and fetches in the background |
| `subscript[key]` | `String` | Returns localized string or key name as fallback |
| `string(_:args:)` | `String` | Formats ICU MessageFormat patterns with arguments |
| `isReady` | `Bool` | `true` after first bundle loads (cache or network) |
| `currentLocale` | `String` | Active BCP 47 locale |
| `revision` | `Int` | Current bundle revision, `0` if none |
| `onStringsUpdated` | Callback | Fires on bundle update with `(locale, revision)` |
| `setLocale(_:)` | `async` | Switches locale, loads cache, fetches latest |
| `refresh()` | `async` | Fetches latest bundle from CDN |

### `AirStringsConfiguration`

```swift
AirStringsConfiguration(
    organizationId: String,        // Your AirStrings organization ID
    projectId: String,             // Your AirStrings project ID
    environmentId: String,         // Your AirStrings environment ID
    publicKeys: [String],          // base64-encoded Ed25519 public keys
    locale: AirStringsLocale,      // .system (default) or .fixed("en-US")
    apiBaseURL: URL,               // defaults to https://api.airstrings.com
    seedBundle: Bundle,            // bundle probed for bundled fallback, defaults to .main
    seedSubdirectory: String,      // seed directory, defaults to "airstrings/bundles"
    isSeedingEnabled: Bool         // defaults to true
)
```

### `AirStringsLocale`

| Case | Description |
|------|-------------|
| `.system` | Uses device locale (default) |
| `.fixed(String)` | Always uses the specified BCP 47 tag |

### `AirStringsError`

| Case | When |
|------|------|
| `.unknownKeyId(String)` | Bundle references a key_id not in your config |
| `.signatureVerificationFailed` | Ed25519 signature doesn't match |
| `.unsupportedFormatVersion(Int)` | Bundle format version not recognized |
| `.invalidSignatureEncoding` | Signature isn't valid base64url or isn't 64 bytes |
| `.invalidPublicKeyEncoding(String)` | Public key isn't valid base64 |
| `.bundleDecodingFailed(String)` | Bundle JSON couldn't be parsed |
| `.seedProjectMismatch(expected:found:)` | Seed bundle's `project_id` doesn't match your configuration |
| `.seedLocaleMismatch(expected:found:)` | Seed file contains a bundle for a different locale than its file name |

## Key Rotation

Configure multiple public keys to support rotation:

```swift
let airStrings = AirStrings(configuration: .init(
    organizationId: "org_a1b2c3d4e5f6",
    projectId: "proj_a1b2c3d4e5f6",
    environmentId: "env_a1b2c3d4e5f6",
    publicKeys: [
        "OLD_KEY_BASE64",
        "NEW_KEY_BASE64"
    ]
))
```

The SDK selects the correct key using the `key_id` in each bundle. Remove old keys after all clients have updated.

## Security

- Every bundle is Ed25519-signed. There is no unsigned delivery path
- Signature covers all metadata (project_id, locale, revision, format_version, created_at) to prevent substitution and downgrade attacks
- Cached bundles are re-verified on every load
- Bundled fallback seeds are untrusted input: each seed runs the full verification pipeline plus `project_id` and locale cross-checks before use
- Anti-downgrade protection: newer revisions are never replaced by older ones, whether they come from cache, seed, or network
- Public keys are provided at init — never hardcoded, logged, or embedded by the SDK
- Uses Apple CryptoKit — no custom cryptography

## Links

- **Website:** https://airstrings.com

## License

MIT — see [LICENSE](LICENSE).
