import Testing
import Foundation
@testable import AirStrings

@Suite("CanonicalJSON")
struct CanonicalJSONTests {

  private func textEntry(_ value: String) -> StringEntry {
    StringEntry(value: value, format: .text)
  }

  private func icuEntry(_ value: String) -> StringEntry {
    StringEntry(value: value, format: .icu)
  }

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
        "onboarding.welcome_title": textEntry("Welcome to Acme"),
        "onboarding.welcome_body": textEntry("Get started in minutes."),
        "settings.language": textEntry("Language"),
        "items.count": icuEntry("{count, plural, one {# item} other {# items}}"),
        "error.network": textEntry("Something went wrong. Please try again.")
      ]
    )

    let result = CanonicalJSON.signedContent(from: bundle)
    let resultString = String(data: result, encoding: .utf8)!

    // Matches the contract example in docs/contracts/bundle-format.md
    let expected = """
      {"format_version":1,"project_id":"proj_a1b2c3d4e5f6","locale":"en-US","revision":42,"created_at":"2026-02-25T14:30:00Z","strings":{"error.network":{"format":"text","value":"Something went wrong. Please try again."},"items.count":{"format":"icu","value":"{count, plural, one {# item} other {# items}}"},"onboarding.welcome_body":{"format":"text","value":"Get started in minutes."},"onboarding.welcome_title":{"format":"text","value":"Welcome to Acme"},"settings.language":{"format":"text","value":"Language"}}}
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
      strings: [
        "z.last": textEntry("Z"),
        "a.first": textEntry("A"),
        "m.middle": textEntry("M")
      ]
    )

    let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

    #expect(result.contains(
      "\"a.first\":{\"format\":\"text\",\"value\":\"A\"}," +
      "\"m.middle\":{\"format\":\"text\",\"value\":\"M\"}," +
      "\"z.last\":{\"format\":\"text\",\"value\":\"Z\"}"
    ))
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
      strings: ["key": textEntry("value")]
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
      strings: ["key": textEntry("line1\nline2\ttab \"quoted\" back\\slash")]
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
      strings: ["key": textEntry("before\u{01}after")]
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

  @Test func stringEntrySortedKeysInsideObject() {
    // Verify "format" sorts before "value" (lexicographic)
    let bundle = StringBundle(
      formatVersion: 1,
      projectId: "proj_test12345678",
      locale: "en",
      revision: 1,
      createdAt: "2026-01-01T00:00:00Z",
      keyId: "key_test_01",
      signature: "dummy",
      strings: ["hello": textEntry("Hello")]
    )

    let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

    #expect(result.contains("\"hello\":{\"format\":\"text\",\"value\":\"Hello\"}"))
  }

  @Test func experimentsContractExample() {
    let bundle = StringBundle(
      formatVersion: 1,
      projectId: "proj_x",
      locale: "en-US",
      revision: 42,
      createdAt: "2026-07-14T10:00:00Z",
      keyId: "key_prod_01",
      signature: "dummy",
      strings: [
        "checkout.cta": StringEntry(
          value: "Continue",
          format: .text,
          experiment: Experiment(
            id: "exp_a1b2c3d4e5f6",
            allocation: ["control": 50, "variant_a": 50],
            variants: ["variant_a": "Continue"]
          )
        )
      ]
    )

    let resultString = String(decoding: CanonicalJSON.experimentsSignedContent(from: bundle), as: UTF8.self)

    let expected = #"{"format_version":1,"project_id":"proj_x","locale":"en-US","revision":42,"created_at":"2026-07-14T10:00:00Z","experiments":{"checkout.cta":{"allocation":{"control":50,"variant_a":50},"id":"exp_a1b2c3d4e5f6","variants":{"variant_a":"Continue"}}}}"#

    #expect(resultString == expected)
  }

  @Test func icuFormatInCanonicalJSON() {
    let bundle = StringBundle(
      formatVersion: 1,
      projectId: "proj_test12345678",
      locale: "en",
      revision: 1,
      createdAt: "2026-01-01T00:00:00Z",
      keyId: "key_test_01",
      signature: "dummy",
      strings: ["count": StringEntry(value: "{n, plural, one {# thing} other {# things}}", format: .icu)]
    )

    let result = String(data: CanonicalJSON.signedContent(from: bundle), encoding: .utf8)!

    #expect(result.contains("\"count\":{\"format\":\"icu\",\"value\":\"{n, plural, one {# thing} other {# things}}\"}"))
  }
}
