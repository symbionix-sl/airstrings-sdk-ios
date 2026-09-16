import CryptoKit
import Testing
import Foundation
@testable import AirStrings

@Suite("FailoverDelivery")
@MainActor
final class FailoverDeliveryTests {
  private let root: URL
  private let store: BundleStore
  private let privateKey = Curve25519.Signing.PrivateKey()

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AirStringsFailoverTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = BundleStore(baseDirectory: root.appendingPathComponent("store", isDirectory: true))
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  private var keyBase64: String {
    privateKey.publicKey.rawRepresentation.base64EncodedString()
  }

  private func makeSignedBundle(revision: Int, value: String) throws -> StringBundle {
    let strings = ["hello": StringEntry(value: value, format: .text)]
    let unsigned = StringBundle(
      formatVersion: 1,
      projectId: "proj_test12345678",
      locale: "en",
      revision: revision,
      createdAt: "2026-06-10T12:00:00Z",
      keyId: keyBase64,
      signature: "",
      strings: strings
    )
    let signature = try privateKey.signature(for: CanonicalJSON.signedContent(from: unsigned))
    return StringBundle(
      formatVersion: 1,
      projectId: "proj_test12345678",
      locale: "en",
      revision: revision,
      createdAt: "2026-06-10T12:00:00Z",
      keyId: keyBase64,
      signature: Base64URL.encode(signature),
      strings: strings
    )
  }

  private func serving(_ bundle: StringBundle) throws -> LoopbackServer {
    LoopbackServer(.respond(status: 200, body: try JSONEncoder().encode(bundle)))
  }

  private func bootstrapServer(_ json: [String: String]) throws -> LoopbackServer {
    LoopbackServer(.respond(status: 200, body: try JSONSerialization.data(withJSONObject: json)))
  }

  private func unreachableServer() -> LoopbackServer {
    let server = LoopbackServer(.hang)
    server.stop()
    return server
  }

  @discardableResult
  private func cacheBundle(_ bundle: StringBundle) throws -> Data {
    let data = try JSONEncoder().encode(bundle)
    store.save(data, projectId: "proj_test12345678", environmentId: "env_test12345678", locale: "en", etag: nil)
    return data
  }

  private func loadCache() -> Data? {
    store.load(projectId: "proj_test12345678", environmentId: "env_test12345678", locale: "en")?.data
  }

  private func makeSUT(api: LoopbackServer) -> AirStrings {
    AirStrings(
      configuration: AirStringsConfiguration(
        organizationId: "org_test12345678",
        projectId: "proj_test12345678",
        environmentId: "env_test12345678",
        publicKeys: [keyBase64],
        locale: .fixed("en"),
        apiBaseURL: api.url,
        isSeedingEnabled: false
      ),
      store: store
    )
  }

  @Test func bootstrapFallbackUsedWhenCDNUnreachable() async throws {
    let cdn = unreachableServer()
    let fallback = try serving(makeSignedBundle(revision: 3, value: "Hello from fallback"))
    let api = try bootstrapServer([
      "cdn_base_url": cdn.url.absoluteString,
      "fallback_base_url": fallback.url.absoluteString,
    ])
    defer { fallback.stop(); api.stop() }

    let sut = makeSUT(api: api)
    await sut.refresh()

    #expect(fallback.hits >= 1)
    #expect(sut.isReady)
    #expect(sut.revision == 3)
    #expect(sut["hello"] == "Hello from fallback")
  }

  @Test func bootstrapWithoutFallbackFieldLoadsFromCDN() async throws {
    let cdn = try serving(makeSignedBundle(revision: 2, value: "Hello from CDN"))
    let fallback = try serving(makeSignedBundle(revision: 9, value: "Hello from fallback"))
    let api = try bootstrapServer([
      "cdn_base_url": cdn.url.absoluteString,
      "future_field": fallback.url.absoluteString,
    ])
    defer { cdn.stop(); fallback.stop(); api.stop() }

    let sut = makeSUT(api: api)
    await sut.refresh()

    #expect(cdn.hits >= 1)
    #expect(fallback.hits == 0)
    #expect(sut.revision == 2)
    #expect(sut["hello"] == "Hello from CDN")
  }

  @Test func invalidSignatureFromFallbackRejectedCacheKept() async throws {
    let cached = try cacheBundle(makeSignedBundle(revision: 1, value: "Hello cached"))
    let signed = try makeSignedBundle(revision: 5, value: "Hello signed")
    let tampered = StringBundle(
      formatVersion: signed.formatVersion,
      projectId: signed.projectId,
      locale: signed.locale,
      revision: signed.revision,
      createdAt: signed.createdAt,
      keyId: signed.keyId,
      signature: signed.signature,
      strings: ["hello": StringEntry(value: "Hello tampered", format: .text)]
    )
    let cdn = unreachableServer()
    let fallback = try serving(tampered)
    let api = try bootstrapServer([
      "cdn_base_url": cdn.url.absoluteString,
      "fallback_base_url": fallback.url.absoluteString,
    ])
    defer { fallback.stop(); api.stop() }

    let sut = makeSUT(api: api)
    await sut.refresh()

    #expect(fallback.hits >= 1)
    #expect(sut.isReady)
    #expect(sut.revision == 1)
    #expect(sut["hello"] == "Hello cached")
    #expect(loadCache() == cached)
  }

  @Test func bothHostsFailKeepsCache() async throws {
    let cached = try cacheBundle(makeSignedBundle(revision: 1, value: "Hello cached"))
    let cdn = unreachableServer()
    let fallback = LoopbackServer(.respond(status: 503))
    let api = try bootstrapServer([
      "cdn_base_url": cdn.url.absoluteString,
      "fallback_base_url": fallback.url.absoluteString,
    ])
    defer { fallback.stop(); api.stop() }

    let sut = makeSUT(api: api)
    await sut.refresh()

    #expect(fallback.hits >= 1)
    #expect(sut.isReady)
    #expect(sut.revision == 1)
    #expect(sut["hello"] == "Hello cached")
    #expect(loadCache() == cached)
  }
}
