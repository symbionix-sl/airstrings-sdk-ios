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
    .package(url: "https://github.com/symbionix/airstrings-sdk-ios.git", from: "1.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies** and enter the repository URL.

## Quick Start

Configure once at app launch:

```swift
import AirStrings

AirStrings.configure(.init(
    projectId: "proj_a1b2c3d4e5f6",
    publicKeys: [
        "key_prod_01": Data([/* your 32-byte Ed25519 public key */])
    ]
))
```

Then use `AirStrings.shared` anywhere:

```swift
// ViewModel, service, UIKit controller — anywhere on MainActor
let title = AirStrings.shared["onboarding.welcome_title"]
```

### SwiftUI

Inject the shared instance at the root for `@Environment` access:

```swift
@main
struct MyApp: App {
    init() {
        AirStrings.configure(.init(
            projectId: "proj_a1b2c3d4e5f6",
            publicKeys: ["key_prod_01": publicKeyData]
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.airStrings, .shared)
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

Access the shared instance directly — no injection needed:

```swift
@MainActor
@Observable
final class SettingsViewModel {
    var title: String {
        AirStrings.shared["settings.title"]
    }

    var itemCount: String {
        AirStrings.shared.string("items.count", args: ["count": items.count])
    }
}
```

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
AirStrings.configure(.init(
    projectId: "proj_a1b2c3d4e5f6",
    publicKeys: ["key_prod_01": publicKeyData],
    locale: .fixed("fr")
))
```

Switch locale at runtime:

```swift
await AirStrings.shared.setLocale("es")
```

## How It Works

1. On init, loads cached bundle from disk (if available) and fetches the latest from CDN
2. Every bundle is Ed25519-signed. Verification is mandatory — invalid signatures are a hard error
3. Verified bundles are cached to `Library/Caches/AirStrings/` for offline use
4. Cached bundles are re-verified on every load (defense in depth)
5. Auto-refreshes when the app returns to foreground
6. Uses `ETag` / `If-None-Match` to avoid re-downloading unchanged bundles
7. If no bundle is available (no cache + no network), string keys are returned as fallback

## API

### `AirStrings`

| Member | Type | Description |
|--------|------|-------------|
| `configure(_:)` | `static` | Configures the shared instance (call once at launch) |
| `shared` | `static` | The shared instance, available after `configure(_:)` |
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
    projectId: String,             // Your AirStrings project ID
    publicKeys: [String: Data],    // key_id → 32-byte Ed25519 public key
    locale: AirStringsLocale       // .system (default) or .fixed("en-US")
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
| `.bundleDecodingFailed(String)` | Bundle JSON couldn't be parsed |

## Key Rotation

Configure multiple public keys to support rotation:

```swift
AirStrings.configure(.init(
    projectId: "proj_a1b2c3d4e5f6",
    publicKeys: [
        "key_prod_01": oldKeyData,
        "key_prod_02": newKeyData
    ]
))
```

The SDK selects the correct key using the `key_id` in each bundle. Remove old keys after all clients have updated.

## Security

- Every bundle is Ed25519-signed. There is no unsigned delivery path
- Signature covers all metadata (project_id, locale, revision, format_version, created_at) to prevent substitution and downgrade attacks
- Cached bundles are re-verified on every load
- Anti-downgrade protection: newer revisions are never replaced by older ones
- Public keys are provided at init — never hardcoded, logged, or embedded by the SDK
- Uses Apple CryptoKit — no custom cryptography

## License

Apache 2.0 — see [LICENSE](LICENSE).
