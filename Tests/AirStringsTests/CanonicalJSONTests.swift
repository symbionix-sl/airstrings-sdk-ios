import XCTest
@testable import AirStrings

final class CanonicalJSONTests: XCTestCase {

    func testContractExample() {
        // From bundle-format.md — the canonical signed content for the example bundle
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_a1b2c3d4e5f6",
            locale: "en-US",
            revision: 42,
            createdAt: "2026-02-25T14:30:00Z",
            keyId: "key_prod_01",
            signature: "dummy",
            strings: [
                "onboarding.welcome_title": "Welcome to Acme",
                "onboarding.welcome_body": "Get started in minutes.",
                "settings.language": "Language",
                "error.network": "Something went wrong. Please try again."
            ]
        )

        let result = CanonicalJSON.signedContent(from: bundle)
        let resultString = String(data: result, encoding: .utf8)!

        let expected = """
        {"format_version":1,"project_id":"proj_a1b2c3d4e5f6","locale":"en-US","revision":42,"created_at":"2026-02-25T14:30:00Z","strings":{"error.network":"Something went wrong. Please try again.","onboarding.welcome_body":"Get started in minutes.","onboarding.welcome_title":"Welcome to Acme","settings.language":"Language"}}
        """

        XCTAssertEqual(resultString, expected)
    }

    func testKeysSortedAlphabetically() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 1,
            createdAt: "2026-01-01T00:00:00Z",
            keyId: "key_test_01",
            signature: "dummy",
            strings: ["z.last": "Z", "a.first": "A", "m.middle": "M"]
        )

        let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

        // Verify strings keys are sorted: a.first < m.middle < z.last
        XCTAssertTrue(result.contains("\"a.first\":\"A\",\"m.middle\":\"M\",\"z.last\":\"Z\""))
    }

    func testNoWhitespace() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 1,
            createdAt: "2026-01-01T00:00:00Z",
            keyId: "key_test_01",
            signature: "dummy",
            strings: ["key": "value"]
        )

        let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

        // No spaces, no newlines
        XCTAssertFalse(result.contains(" "))
        XCTAssertFalse(result.contains("\n"))
    }

    func testIntegersNotFloats() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 100,
            createdAt: "2026-01-01T00:00:00Z",
            keyId: "key_test_01",
            signature: "dummy",
            strings: [:]
        )

        let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

        XCTAssertTrue(result.contains("\"format_version\":1,"))
        XCTAssertTrue(result.contains("\"revision\":100,\"created_at\""))
        XCTAssertFalse(result.contains("1.0"))
        XCTAssertFalse(result.contains("100.0"))
    }

    func testStringEscaping() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 1,
            createdAt: "2026-01-01T00:00:00Z",
            keyId: "key_test_01",
            signature: "dummy",
            strings: ["key": "line1\nline2\ttab \"quoted\" back\\slash"]
        )

        let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

        XCTAssertTrue(result.contains("line1\\nline2\\ttab \\\"quoted\\\" back\\\\slash"))
    }

    func testControlCharacterEscaping() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 1,
            createdAt: "2026-01-01T00:00:00Z",
            keyId: "key_test_01",
            signature: "dummy",
            strings: ["key": "before\u{01}after"]
        )

        let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

        XCTAssertTrue(result.contains("before\\u0001after"))
    }

    func testEmptyStringsObject() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 1,
            createdAt: "2026-01-01T00:00:00Z",
            keyId: "key_test_01",
            signature: "dummy",
            strings: [:]
        )

        let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

        XCTAssertTrue(result.hasSuffix("\"strings\":{}}"))
    }
}
