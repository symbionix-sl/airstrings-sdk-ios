public enum AirStringsError: Error, Sendable {
  case unknownKeyId(String)
  case signatureVerificationFailed
  case unsupportedFormatVersion(Int)
  case bundleDecodingFailed(String)
  case invalidSignatureEncoding
  case invalidPublicKeyEncoding(String)
}
