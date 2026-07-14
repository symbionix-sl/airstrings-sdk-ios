import CryptoKit
import Testing
import Foundation
@testable import AirStrings

@Suite("BundleVerifier")
struct BundleVerifierTests {

  private func textEntry(_ value: String) -> StringEntry {
    StringEntry(value: value, format: .text)
  }

  private func keyBase64(_ privateKey: Curve25519.Signing.PrivateKey) -> String {
    privateKey.publicKey.rawRepresentation.base64EncodedString()
  }

  private func makeSignedBundle(
    formatVersion: Int = 1,
    projectId: String = "proj_test12345678",
    locale: String = "en",
    revision: Int = 1,
    createdAt: String = "2026-02-25T14:30:00Z",
    keyId: String? = nil,
    strings: [String: StringEntry] = ["hello": StringEntry(value: "Hello World", format: .text)],
    privateKey: Curve25519.Signing.PrivateKey
  ) throws -> StringBundle {
    let resolvedKeyId = keyId ?? keyBase64(privateKey)

    let unsigned = StringBundle(
      formatVersion: formatVersion,
      projectId: projectId,
      locale: locale,
      revision: revision,
      createdAt: createdAt,
      keyId: resolvedKeyId,
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
      keyId: resolvedKeyId,
      signature: signatureBase64url,
      strings: strings
    )
  }

  @Test func validSignature() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(privateKey: privateKey)
    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

    try verifier.verify(bundle)
  }

  @Test func wrongSignatureThrows() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let wrongKey = Curve25519.Signing.PrivateKey()
    // Bundle signed with signingKey but keyId set to wrongKey's base64
    let bundle = try makeSignedBundle(keyId: keyBase64(wrongKey), privateKey: signingKey)
    let verifier = BundleVerifier(publicKeys: [keyBase64(wrongKey)])

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
    let otherKey = Curve25519.Signing.PrivateKey()
    // Bundle's keyId is privateKey's base64, but verifier only knows otherKey
    let bundle = try makeSignedBundle(privateKey: privateKey)
    let verifier = BundleVerifier(publicKeys: [keyBase64(otherKey)])

    let error = #expect(throws: AirStringsError.self) {
      try verifier.verify(bundle)
    }
    guard case .unknownKeyId = error else {
      Issue.record("Expected unknownKeyId, got \(String(describing: error))")
      return
    }
  }

  @Test func unsupportedFormatVersionThrows() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try makeSignedBundle(formatVersion: 99, privateKey: privateKey)
    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

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
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = StringBundle(
      formatVersion: 1,
      projectId: "proj_test12345678",
      locale: "en",
      revision: 1,
      createdAt: "2026-02-25T14:30:00Z",
      keyId: keyBase64(privateKey),
      signature: "not-valid-base64url-!!@@##",
      strings: ["hello": textEntry("Hello")]
    )

    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

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

    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

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

    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

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

    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

    try verifier.verify(bundle)
  }

  private func experimentEntry(
    allocation: [String: Int] = ["control": 50, "variant_a": 50]
  ) -> StringEntry {
    StringEntry(
      value: "Continue",
      format: .text,
      experiment: Experiment(
        id: "exp_a1b2c3d4e5f6",
        allocation: allocation,
        variants: ["variant_a": "Continue"]
      )
    )
  }

  private func signedExperimentsBundle(
    strings: [String: StringEntry],
    privateKey: Curve25519.Signing.PrivateKey
  ) throws -> StringBundle {
    let resolvedKeyId = keyBase64(privateKey)
    let unsigned = StringBundle(
      formatVersion: 1,
      projectId: "proj_x",
      locale: "en-US",
      revision: 42,
      createdAt: "2026-07-14T10:00:00Z",
      keyId: resolvedKeyId,
      signature: "",
      strings: strings
    )
    let canonicalBytes = CanonicalJSON.experimentsSignedContent(from: unsigned)
    let signature = Base64URL.encode(try privateKey.signature(for: canonicalBytes))
    return StringBundle(
      formatVersion: 1,
      projectId: "proj_x",
      locale: "en-US",
      revision: 42,
      createdAt: "2026-07-14T10:00:00Z",
      keyId: resolvedKeyId,
      signature: "",
      strings: strings,
      experimentsSignature: signature
    )
  }

  @Test func validExperimentsSignatureVerifies() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = try signedExperimentsBundle(
      strings: ["checkout.cta": experimentEntry()],
      privateKey: privateKey
    )
    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

    #expect(verifier.verifyExperiments(bundle))
  }

  @Test func tamperedAllocationFailsExperimentsVerification() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let original = try signedExperimentsBundle(
      strings: ["checkout.cta": experimentEntry()],
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
      strings: ["checkout.cta": experimentEntry(allocation: ["control": 10, "variant_a": 90])],
      experimentsSignature: original.experimentsSignature
    )
    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

    #expect(!verifier.verifyExperiments(tampered))
  }

  @Test func nilExperimentsSignatureFails() {
    let privateKey = Curve25519.Signing.PrivateKey()
    let bundle = StringBundle(
      formatVersion: 1,
      projectId: "proj_x",
      locale: "en-US",
      revision: 42,
      createdAt: "2026-07-14T10:00:00Z",
      keyId: keyBase64(privateKey),
      signature: "",
      strings: ["checkout.cta": experimentEntry()],
      experimentsSignature: nil
    )
    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

    #expect(!verifier.verifyExperiments(bundle))
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

    let verifier = BundleVerifier(publicKeys: [keyBase64(privateKey)])

    #expect(throws: AirStringsError.self) {
      try verifier.verify(tampered)
    }
  }
}
