import Foundation

/// Static configuration for the demo app.
/// The public key is generated into DemoConfig.generated.swift (gitignored).
enum DemoConfig {
  static let projectId = "proj_demo00000001"

  /// MinIO endpoint — SDK builds: {baseURL}/v1/{projectId}/{locale}/bundle.json
  static let baseURL = URL(string: "http://localhost:9000/airstrings-bundles/bundles")!

  /// Locales seeded by seed.sh.
  static let availableLocales = ["en", "fr", "es"]

  /// Backend API URL (used by seed.sh, not the SDK).
  static let serverURL = "http://localhost:8080"
}
