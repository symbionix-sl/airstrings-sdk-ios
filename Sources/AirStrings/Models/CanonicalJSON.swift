import Foundation

/// Produces the canonical JSON byte string used for Ed25519 signature verification.
///
/// Canonical JSON rules (matching RFC 8785 / JCS subset):
/// - No whitespace between tokens
/// - Object keys sorted lexicographically by Unicode code point (recursive)
/// - No trailing commas
/// - Integers serialized without `.0`
/// - Strings escaped per RFC 8259 (only `"`, `\`, and control chars U+0000–U+001F)
/// - UTF-8 encoding, no BOM
enum CanonicalJSON {
  /// Builds the signed content from a bundle: format_version, project_id, locale,
  /// revision, created_at, and strings — field order matches the backend/contract.
  static func signedContent(from bundle: StringBundle) -> Data {
    // Top-level field order matches backend: format_version, project_id, locale, revision, created_at, strings
    // The strings object keys are sorted lexicographically.
    var json = "{"
    json += "\"format_version\":" + String(bundle.formatVersion)
    json += ",\"project_id\":" + escapeString(bundle.projectId)
    json += ",\"locale\":" + escapeString(bundle.locale)
    json += ",\"revision\":" + String(bundle.revision)
    json += ",\"created_at\":" + escapeString(bundle.createdAt)
    json += ",\"strings\":{"

    let sortedKeys = bundle.strings.keys.sorted()
    for (i, key) in sortedKeys.enumerated() {
      if i > 0 { json += "," }
      let entry = bundle.strings[key]!
      json += escapeString(key) + ":{"
      json += "\"format\":" + escapeString(entry.format.rawValue)
      json += ",\"value\":" + escapeString(entry.value)
      json += "}"
    }

    json += "}}"
    return Data(json.utf8)
  }

  private static func escapeString(_ s: String) -> String {
    var result = "\""
    for scalar in s.unicodeScalars {
      switch scalar {
      case "\"":
        result += "\\\""
      case "\\":
        result += "\\\\"
      case "\u{08}":
        result += "\\b"
      case "\u{0C}":
        result += "\\f"
      case "\n":
        result += "\\n"
      case "\r":
        result += "\\r"
      case "\t":
        result += "\\t"
      default:
        if scalar.value < 0x20 {
          result += String(format: "\\u%04x", scalar.value)
        } else {
          result += String(scalar)
        }
      }
    }
    result += "\""
    return result
  }
}
