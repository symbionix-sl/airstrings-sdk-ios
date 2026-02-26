import XCTest
@testable import AirStrings

final class Base64URLTests: XCTestCase {

    func testDecodeValidBase64url() {
        // "Hello" in base64url = "SGVsbG8"
        let decoded = Base64URL.decode("SGVsbG8")
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), "Hello")
    }

    func testDecodeWithURLSafeCharacters() {
        // Base64url uses - instead of + and _ instead of /
        // Standard base64: "a+b/c==" → base64url: "a-b_c"
        let standard = Data(base64Encoded: "a+b/cw==")!
        let decoded = Base64URL.decode("a-b_cw")
        XCTAssertEqual(decoded, standard)
    }

    func testDecodeHandlesMissingPadding() {
        // Base64 for "ab" = "YWI=" (1 padding char)
        // Base64url for "ab" = "YWI" (no padding)
        let decoded = Base64URL.decode("YWI")
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), "ab")
    }

    func testEncodeThenDecode() {
        let original = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let encoded = Base64URL.encode(original)
        let decoded = Base64URL.decode(encoded)

        XCTAssertEqual(decoded, original)
        // Verify no standard base64 characters
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }

    func testDecode64ByteSignature() {
        // Ed25519 signatures are exactly 64 bytes
        let signatureBytes = Data(repeating: 0xAB, count: 64)
        let encoded = Base64URL.encode(signatureBytes)

        // 64 bytes → 86 base64url chars (ceil(64*4/3) = 88, minus 2 padding)
        XCTAssertEqual(encoded.count, 86)

        let decoded = Base64URL.decode(encoded)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 64)
        XCTAssertEqual(decoded, signatureBytes)
    }

    func testDecodeEmptyString() {
        let decoded = Base64URL.decode("")
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 0)
    }
}
