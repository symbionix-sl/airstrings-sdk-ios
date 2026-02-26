import Testing
import Foundation
@testable import AirStrings

@Suite("Base64URL")
struct Base64URLTests {

  @Test func decodeValidBase64url() {
    let decoded = Base64URL.decode("SGVsbG8")
    #expect(decoded != nil)
    #expect(String(data: decoded!, encoding: .utf8) == "Hello")
  }

  @Test func decodeWithURLSafeCharacters() {
    let standard = Data(base64Encoded: "a+b/cw==")!
    let decoded = Base64URL.decode("a-b_cw")
    #expect(decoded == standard)
  }

  @Test func decodeHandlesMissingPadding() {
    let decoded = Base64URL.decode("YWI")
    #expect(decoded != nil)
    #expect(String(data: decoded!, encoding: .utf8) == "ab")
  }

  @Test func encodeThenDecode() {
    let original = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
    let encoded = Base64URL.encode(original)
    let decoded = Base64URL.decode(encoded)
    #expect(decoded == original)
    #expect(!encoded.contains("+"))
    #expect(!encoded.contains("/"))
    #expect(!encoded.contains("="))
  }

  @Test func decode64ByteSignature() {
    let signatureBytes = Data(repeating: 0xAB, count: 64)
    let encoded = Base64URL.encode(signatureBytes)
    #expect(encoded.count == 86)
    let decoded = Base64URL.decode(encoded)
    #expect(decoded != nil)
    #expect(decoded?.count == 64)
    #expect(decoded == signatureBytes)
  }

  @Test func decodeEmptyString() {
    let decoded = Base64URL.decode("")
    #expect(decoded != nil)
    #expect(decoded?.count == 0)
  }
}
