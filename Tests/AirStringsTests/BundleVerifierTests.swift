import CryptoKit
import Testing
import Foundation
@testable import AirStrings

@Suite("BundleVerifier")
struct BundleVerifierTests {

  private func textEntry(_ value: String) -> StringEntry {
    StringEntry(value: value, format: .text)
  }

  private func makeSignedBundle(
    formatVersion: Int = 1,
    projectId: String = "proj_test12345678",
    locale: String = "en",
    revision: Int = 1,
    createdAt: String = "2026-02-25T14:30:00Z",
    keyId: String = "key_test_01",
    strings: [String: StringEntry] = ["hello": StringEntry(value: "Hello World", format: .text)],
    privateKey: Curve25519.Signing.PrivateKey
  ) throws -> StringBundle {
    let unsigned = StringBundle(
      formatVersion: formatVersion,
      projectId: projectId,
      locale: locale,
      revision: revision,
      createdAt: createdAt,
      keyId: keyId,
      signature: "",
      strings: strings
    )

    let canonicalBytes = CanonicalJSON.signedContent(from: unsigned)
    let signatureData = try privateKey.signature(for: canonicalBytes)
    let signatureBase64url = Base64URL.encode(signatureData)

    return StringBundle(
      formatVersion: formatVersion,
      projectId: projectId,
      locale: locale,
      revision: revision,
      createdAt: createdAt,
      keyId: keyId,
      signature: signatureBase64url,
      strings: strings
    )
  }

  @Test func validSignature() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(privateKey: privateKey)
    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    try verifier.verify(bundle)
  }

  @Test func wrongSignatureThrows() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let wrongKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(privateKey: signingKey)
    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": wrongKey.publicKey.rawRepresentation
    ])

    let error = #expect(throws: AirStringsError.self) {
      try verifier.verify(bundle)
    }
    guard case .signatureVerificationFailed = error else {
      Issue.record("Expected signatureVerificationFailed, got \(String(describing: error))")
      return
    }
  }

  @Test func unknownKeyIdThrows() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(keyId: "key_unknown_99", privateKey: privateKey)
    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    let error = #expect(throws: AirStringsError.self) {
      try verifier.verify(bundle)
    }
    guard case .unknownKeyId(let keyId) = error else {
      Issue.record("Expected unknownKeyId, got \(String(describing: error))")
      return
    }
    #expect(keyId == "key_unknown_99")
  }

  @Test func unsupportedFormatVersionThrows() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(formatVersion: 99, privateKey: privateKey)
    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    let error = #expect(throws: AirStringsError.self) {
      try verifier.verify(bundle)
    }
    guard case .unsupportedFormatVersion(let version) = error else {
      Issue.record("Expected unsupportedFormatVersion, got \(String(describing: error))")
      return
    }
    #expect(version == 99)
  }

  @Test func invalidSignatureEncodingThrows() {
    let bundle = StringBundle(
      formatVersion: 1,
      projectId: "proj_test12345678",
      locale: "en",
      revision: 1,
      createdAt: "2026-02-25T14:30:00Z",
      keyId: "key_test_01",
      signature: "not-valid-base64url-!!@@##",
      strings: ["hello": textEntry("Hello")]
    )

    let privateKey = Curve25519.Signing.PrivateKey()
    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    #expect(throws: AirStringsError.self) {
      try verifier.verify(bundle)
    }
  }

  @Test func signatureWithMultipleStrings() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(
      strings: [
        "z.last": textEntry("Last"),
        "a.first": textEntry("First"),
        "m.middle": textEntry("Middle")
      ],
      privateKey: privateKey
    )

    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    try verifier.verify(bundle)
  }

  @Test func tamperedStringsFailVerification() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let original = try makeSignedBundle(
      strings: ["key": textEntry("original")],
      privateKey: privateKey
    )

    let tampered = StringBundle(
      formatVersion: original.formatVersion,
      projectId: original.projectId,
      locale: original.locale,
      revision: original.revision,
      createdAt: original.createdAt,
      keyId: original.keyId,
      signature: original.signature,
      strings: ["key": textEntry("tampered")]
    )

    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    let error = #expect(throws: AirStringsError.self) {
      try verifier.verify(tampered)
    }
    guard case .signatureVerificationFailed = error else {
      Issue.record("Expected signatureVerificationFailed, got \(String(describing: error))")
      return
    }
  }

  @Test func signatureWithICUStrings() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(
      strings: [
        "greeting": StringEntry(value: "Hello", format: .text),
        "items": StringEntry(value: "{count, plural, one {# item} other {# items}}", format: .icu)
      ],
      privateKey: privateKey
    )

    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    try verifier.verify(bundle)
  }

  @Test func tamperedFormatFieldFailsVerification() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let original = try makeSignedBundle(
      strings: ["key": StringEntry(value: "Hello", format: .text)],
      privateKey: privateKey
    )

    // Tamper: change format from text to icu while keeping same signature
    let tampered = StringBundle(
      formatVersion: original.formatVersion,
      projectId: original.projectId,
      locale: original.locale,
      revision: original.revision,
      createdAt: original.createdAt,
      keyId: original.keyId,
      signature: original.signature,
      strings: ["key": StringEntry(value: "Hello", format: .icu)]
    )

    let verifier = BundleVerifier(publicKeys: [
      "key_test_01": privateKey.publicKey.rawRepresentation
    ])

    #expect(throws: AirStringsError.self) {
      try verifier.verify(tampered)
    }
  }
}
