import Foundation

/// Base64url encoding/decoding per RFC 4648 §5.
/// Uses `-` instead of `+`, `_` instead of `/`, no padding.
enum Base64URL {
  static func decode(_ string: String) -> Data? {
    var base64 = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
      base64 += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: base64)
  }

  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
