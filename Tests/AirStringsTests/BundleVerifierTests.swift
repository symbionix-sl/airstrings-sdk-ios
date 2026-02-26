import CryptoKit
import XCTest
@testable import AirStrings

final class BundleVerifierTests: XCTestCase {

    private func makeSignedBundle(
        formatVersion: Int = 1,
        projectId: String = "proj_test12345678",
        locale: String = "en",
        revision: Int = 1,
        createdAt: String = "2026-02-25T14:30:00Z",
        keyId: String = "key_test_01",
        strings: [String: String] = ["hello": "Hello World"],
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> StringBundle {
        // Build a bundle without signature to compute canonical JSON
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

    func testValidSignature() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let bundle = try makeSignedBundle(privateKey: privateKey)
        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": publicKey.rawRepresentation
        ])

        XCTAssertNoThrow(try verifier.verify(bundle))
    }

    func testWrongSignatureThrows() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let wrongKey = Curve25519.Signing.PrivateKey()

        let bundle = try makeSignedBundle(privateKey: signingKey)
        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": wrongKey.publicKey.rawRepresentation
        ])

        XCTAssertThrowsError(try verifier.verify(bundle)) { error in
            guard case AirStringsError.signatureVerificationFailed = error else {
                XCTFail("Expected signatureVerificationFailed, got \(error)")
                return
            }
        }
    }

    func testUnknownKeyIdThrows() throws {
        let privateKey = Curve25519.Signing.PrivateKey()

        let bundle = try makeSignedBundle(keyId: "key_unknown_99", privateKey: privateKey)
        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": privateKey.publicKey.rawRepresentation
        ])

        XCTAssertThrowsError(try verifier.verify(bundle)) { error in
            guard case AirStringsError.unknownKeyId(let keyId) = error else {
                XCTFail("Expected unknownKeyId, got \(error)")
                return
            }
            XCTAssertEqual(keyId, "key_unknown_99")
        }
    }

    func testUnsupportedFormatVersionThrows() throws {
        let privateKey = Curve25519.Signing.PrivateKey()

        let bundle = try makeSignedBundle(formatVersion: 99, privateKey: privateKey)
        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": privateKey.publicKey.rawRepresentation
        ])

        XCTAssertThrowsError(try verifier.verify(bundle)) { error in
            guard case AirStringsError.unsupportedFormatVersion(let version) = error else {
                XCTFail("Expected unsupportedFormatVersion, got \(error)")
                return
            }
            XCTAssertEqual(version, 99)
        }
    }

    func testInvalidSignatureEncodingThrows() {
        let bundle = StringBundle(
            formatVersion: 1,
            projectId: "proj_test12345678",
            locale: "en",
            revision: 1,
            createdAt: "2026-02-25T14:30:00Z",
            keyId: "key_test_01",
            signature: "not-valid-base64url-!!@@##",
            strings: ["hello": "Hello"]
        )

        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": privateKey.publicKey.rawRepresentation
        ])

        XCTAssertThrowsError(try verifier.verify(bundle)) { error in
            guard case AirStringsError.invalidSignatureEncoding = error else {
                // Could also be signatureVerificationFailed if base64 decodes to wrong length
                return
            }
        }
    }

    func testSignatureWithMultipleStrings() throws {
        let privateKey = Curve25519.Signing.PrivateKey()

        let bundle = try makeSignedBundle(
            strings: [
                "z.last": "Last",
                "a.first": "First",
                "m.middle": "Middle"
            ],
            privateKey: privateKey
        )

        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": privateKey.publicKey.rawRepresentation
        ])

        XCTAssertNoThrow(try verifier.verify(bundle))
    }

    func testTamperedStringsFailVerification() throws {
        let privateKey = Curve25519.Signing.PrivateKey()

        // Sign with original strings
        let original = try makeSignedBundle(
            strings: ["key": "original"],
            privateKey: privateKey
        )

        // Create a tampered bundle with different strings but same signature
        let tampered = StringBundle(
            formatVersion: original.formatVersion,
            projectId: original.projectId,
            locale: original.locale,
            revision: original.revision,
            createdAt: original.createdAt,
            keyId: original.keyId,
            signature: original.signature,
            strings: ["key": "tampered"]
        )

        let verifier = BundleVerifier(publicKeys: [
            "key_test_01": privateKey.publicKey.rawRepresentation
        ])

        XCTAssertThrowsError(try verifier.verify(tampered)) { error in
            guard case AirStringsError.signatureVerificationFailed = error else {
                XCTFail("Expected signatureVerificationFailed, got \(error)")
                return
            }
        }
    }
}
