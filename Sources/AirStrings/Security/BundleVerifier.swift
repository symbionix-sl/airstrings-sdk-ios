import CryptoKit
import Foundation

struct BundleVerifier: Sendable {
  let publicKeys: [String]

  /// Verifies a bundle's Ed25519 signature per the AirStrings contract.
  ///
  /// Verification order (per contract):
  /// 1. Look up key_id (base64 public key) → unknown key = hard error
  /// 2. Build canonical signed content
  /// 3. Verify Ed25519 signature → failure = hard error
  /// 4. Check format_version → unknown version = hard error
  func verify(_ bundle: StringBundle) throws {
    guard publicKeys.contains(bundle.keyId) else {
      throw AirStringsError.unknownKeyId(bundle.keyId)
    }

    guard let keyData = Data(base64Encoded: bundle.keyId) else {
      throw AirStringsError.invalidPublicKeyEncoding(bundle.keyId)
    }

    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let canonicalBytes = CanonicalJSON.signedContent(from: bundle)

    guard let signatureBytes = Base64URL.decode(bundle.signature),
        signatureBytes.count == 64 else {
      throw AirStringsError.invalidSignatureEncoding
    }

    guard publicKey.isValidSignature(signatureBytes, for: canonicalBytes) else {
      throw AirStringsError.signatureVerificationFailed
    }

    guard bundle.formatVersion == 1 else {
      throw AirStringsError.unsupportedFormatVersion(bundle.formatVersion)
    }
  }
}
