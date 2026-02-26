import Testing
import Foundation
@testable import AirStrings

@Suite("CanonicalJSON")
struct CanonicalJSONTests {

  @Test func contractExample() {
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

    #expect(resultString == expected)
  }

  @Test func keysSortedAlphabetically() {
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

    #expect(result.contains("\"a.first\":\"A\",\"m.middle\":\"M\",\"z.last\":\"Z\""))
  }

  @Test func noWhitespace() {
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

    #expect(!result.contains(" "))
    #expect(!result.contains("\n"))
  }

  @Test func integersNotFloats() {
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

    #expect(result.contains("\"format_version\":1,"))
    #expect(result.contains("\"revision\":100,\"created_at\""))
    #expect(!result.contains("1.0"))
    #expect(!result.contains("100.0"))
  }

  @Test func stringEscaping() {
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

    #expect(result.contains("line1\\nline2\\ttab \\\"quoted\\\" back\\\\slash"))
  }

  @Test func controlCharacterEscaping() {
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

    #expect(result.contains("before\\u0001after"))
  }

  @Test func emptyStringsObject() {
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

    #expect(result.hasSuffix("\"strings\":{}}"))
  }
}
