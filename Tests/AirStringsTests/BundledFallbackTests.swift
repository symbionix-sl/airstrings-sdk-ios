import CryptoKit
import Testing
import Foundation
@testable import AirStrings

@Suite("BundledFallback")
@MainActor
final class BundledFallbackTests {
  private let root: URL
  private let appDir: URL
  private let seedDir: URL
  private let store: BundleStore
  private let privateKey: Curve25519.Signing.PrivateKey

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AirStringsSeedTests-\(UUID().uuidString)", isDirectory: true)
    appDir = root.appendingPathComponent("app", isDirectory: true)
    seedDir = appDir
      .appendingPathComponent("airstrings", isDirectory: true)
      .appendingPathComponent("bundles", isDirectory: true)
    try FileManager.default.createDirectory(at: seedDir, withIntermediateDirectories: true)
    store = BundleStore(baseDirectory: root.appendingPathComponent("store", isDirectory: true))
    privateKey = Curve25519.Signing.PrivateKey()
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  private var keyBase64: String {
    privateKey.publicKey.rawRepresentation.base64EncodedString()
  }

  private func textEntry(_ value: String) -> StringEntry {
    StringEntry(value: value, format: .text)
  }

  private func makeSignedBundle(
    projectId: String = "proj_test12345678",
    locale: String = "en",
    revision: Int,
    strings: [String: StringEntry]
  ) throws -> StringBundle {
    let unsigned = StringBundle(
      formatVersion: 1,
      projectId: projectId,
      locale: locale,
      revision: revision,
      createdAt: "2026-06-10T12:00:00Z",
      keyId: keyBase64,
      signature: "",
      strings: strings
    )
    let signature = try privateKey.signature(for: CanonicalJSON.signedContent(from: unsigned))
    return StringBundle(
      formatVersion: 1,
      projectId: projectId,
      locale: locale,
      revision: revision,
      createdAt: "2026-06-10T12:00:00Z",
      keyId: keyBase64,
      signature: Base64URL.encode(signature),
      strings: strings
    )
  }

  @discardableResult
  private func writeSeed(_ bundle: StringBundle, fileLocale: String? = nil) throws -> Data {
    let data = try JSONEncoder().encode(bundle)
    try data.write(to: seedDir.appendingPathComponent("\(fileLocale ?? bundle.locale).json"))
    return data
  }

  @discardableResult
  private func cacheBundle(_ bundle: StringBundle, etag: String? = nil) throws -> Data {
    let data = try JSONEncoder().encode(bundle)
    store.save(
      data,
      projectId: "proj_test12345678",
      environmentId: "env_test12345678",
      locale: bundle.locale,
      etag: etag
    )
    return data
  }

  private func loadCache(locale: String = "en") -> Data? {
    store.load(projectId: "proj_test12345678", environmentId: "env_test12345678", locale: locale)?.data
  }

  private func makeConfig(
    locale: String = "en",
    seedBundle: Bundle? = nil,
    isSeedingEnabled: Bool = true
  ) -> AirStringsConfiguration {
    AirStringsConfiguration(
      organizationId: "org_test12345678",
      projectId: "proj_test12345678",
      environmentId: "env_test12345678",
      publicKeys: [keyBase64],
      locale: .fixed(locale),
      baseURL: URL(string: "https://localhost:9999")!,
      seedBundle: seedBundle ?? Bundle(url: appDir)!,
      isSeedingEnabled: isSeedingEnabled
    )
  }

  private func makeSUT(_ configuration: AirStringsConfiguration) -> AirStrings {
    AirStrings(configuration: configuration, store: store)
  }

  @Test func offlineColdStartServesValidSeed() throws {
    let seed = try makeSignedBundle(revision: 7, strings: ["hello": textEntry("Hello from seed")])
    let seedData = try writeSeed(seed)

    let sut = makeSUT(makeConfig())

    #expect(sut.isReady)
    #expect(sut.revision == 7)
    #expect(sut["hello"] == "Hello from seed")
    #expect(loadCache() == seedData)
  }

  @Test func tamperedSeedIsRejected() throws {
    let original = try makeSignedBundle(revision: 3, strings: ["hello": textEntry("Legit")])
    let tampered = StringBundle(
      formatVersion: original.formatVersion,
      projectId: original.projectId,
      locale: original.locale,
      revision: original.revision,
      createdAt: original.createdAt,
      keyId: original.keyId,
      signature: original.signature,
      strings: ["hello": textEntry("Tampered")]
    )
    try writeSeed(tampered)

    let sut = makeSUT(makeConfig())

    #expect(!sut.isReady)
    #expect(sut.revision == 0)
    #expect(sut["hello"] == "hello")
    #expect(loadCache() == nil)
  }

  @Test func seedOlderThanCacheIsIgnored() throws {
    let cached = try makeSignedBundle(revision: 5, strings: ["greeting": textEntry("From cache")])
    let cachedData = try cacheBundle(cached, etag: "\"rev:5\"")
    let seed = try makeSignedBundle(revision: 4, strings: ["greeting": textEntry("From seed")])
    try writeSeed(seed)

    let sut = makeSUT(makeConfig())

    #expect(sut.isReady)
    #expect(sut.revision == 5)
    #expect(sut["greeting"] == "From cache")
    #expect(loadCache() == cachedData)
  }

  @Test func seedNewerThanCacheWinsAndPersists() throws {
    let cached = try makeSignedBundle(revision: 5, strings: ["greeting": textEntry("From cache")])
    try cacheBundle(cached, etag: "\"rev:5\"")
    let seed = try makeSignedBundle(revision: 6, strings: ["greeting": textEntry("From seed")])
    let seedData = try writeSeed(seed)

    let sut = makeSUT(makeConfig())

    #expect(sut.isReady)
    #expect(sut.revision == 6)
    #expect(sut["greeting"] == "From seed")
    #expect(loadCache() == seedData)
  }

  @Test func revisionTiePrefersCache() throws {
    let cached = try makeSignedBundle(revision: 5, strings: ["greeting": textEntry("From cache")])
    let cachedData = try cacheBundle(cached, etag: "\"rev:5\"")
    let seed = try makeSignedBundle(revision: 5, strings: ["greeting": textEntry("From seed")])
    try writeSeed(seed)

    let sut = makeSUT(makeConfig())

    #expect(sut.revision == 5)
    #expect(sut["greeting"] == "From cache")
    #expect(loadCache() == cachedData)
  }

  @Test func missingSeedResourceWithoutCacheMatchesCurrentBehavior() {
    let sut = makeSUT(makeConfig())

    #expect(!sut.isReady)
    #expect(sut.revision == 0)
    #expect(sut["any.key"] == "any.key")
    #expect(loadCache() == nil)
  }

  @Test func missingSeedDirectoryServesCacheUnchanged() throws {
    let cached = try makeSignedBundle(revision: 2, strings: ["greeting": textEntry("From cache")])
    let cachedData = try cacheBundle(cached, etag: "\"rev:2\"")
    let emptyDir = root.appendingPathComponent("empty", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

    let sut = makeSUT(makeConfig(seedBundle: Bundle(url: emptyDir)!))

    #expect(sut.isReady)
    #expect(sut.revision == 2)
    #expect(sut["greeting"] == "From cache")
    #expect(loadCache() == cachedData)
  }

  @Test func flattenedSeedLayoutIsTreatedAsAbsent() throws {
    let seed = try makeSignedBundle(revision: 7, strings: ["hello": textEntry("Flattened")])
    let flatDir = root.appendingPathComponent("flat", isDirectory: true)
    try FileManager.default.createDirectory(at: flatDir, withIntermediateDirectories: true)
    try JSONEncoder().encode(seed).write(to: flatDir.appendingPathComponent("en.json"))

    let sut = makeSUT(makeConfig(seedBundle: Bundle(url: flatDir)!))

    #expect(!sut.isReady)
    #expect(sut["hello"] == "hello")
    #expect(loadCache() == nil)
  }

  @Test func disabledSeedingIgnoresValidSeed() throws {
    let seed = try makeSignedBundle(revision: 7, strings: ["hello": textEntry("Hello from seed")])
    try writeSeed(seed)

    let sut = makeSUT(makeConfig(isSeedingEnabled: false))

    #expect(!sut.isReady)
    #expect(sut["hello"] == "hello")
    #expect(loadCache() == nil)
  }

  @Test func seedWithWrongProjectIdIsRejected() throws {
    let seed = try makeSignedBundle(
      projectId: "proj_otherproj456",
      revision: 9,
      strings: ["hello": textEntry("Wrong project")]
    )
    try writeSeed(seed)

    let sut = makeSUT(makeConfig())

    #expect(!sut.isReady)
    #expect(sut["hello"] == "hello")
    #expect(loadCache() == nil)
  }

  @Test func seedWithMismatchedLocaleFileIsRejected() throws {
    let seed = try makeSignedBundle(locale: "ja", revision: 9, strings: ["hello": textEntry("こんにちは")])
    try writeSeed(seed, fileLocale: "en")

    let sut = makeSUT(makeConfig())

    #expect(!sut.isReady)
    #expect(sut["hello"] == "hello")
    #expect(loadCache(locale: "en") == nil)
    #expect(loadCache(locale: "ja") == nil)
  }

  @Test func setLocaleSeedsNewLocale() async throws {
    let frSeed = try makeSignedBundle(locale: "fr", revision: 4, strings: ["greeting": textEntry("Bonjour")])
    let frData = try writeSeed(frSeed)

    let sut = makeSUT(makeConfig(locale: "en"))
    #expect(!sut.isReady)

    await sut.setLocale("fr")

    #expect(sut.currentLocale == "fr")
    #expect(sut.isReady)
    #expect(sut.revision == 4)
    #expect(sut["greeting"] == "Bonjour")
    #expect(loadCache(locale: "fr") == frData)
  }

  @Test func seedNeverOverwritesHigherRevisionInMemory() async throws {
    let cached = try makeSignedBundle(revision: 8, strings: ["greeting": textEntry("Live")])
    try cacheBundle(cached, etag: "\"rev:8\"")
    let seed = try makeSignedBundle(revision: 2, strings: ["greeting": textEntry("Seed")])
    try writeSeed(seed)

    let sut = makeSUT(makeConfig())
    #expect(sut.revision == 8)

    store.delete(projectId: "proj_test12345678", environmentId: "env_test12345678", locale: "en")
    await sut.setLocale("en")

    #expect(sut.revision == 8)
    #expect(sut["greeting"] == "Live")
    #expect(loadCache() == nil)
  }

  @Test func seedNeverDowngradesAfterSetLocale() async throws {
    let cached = try makeSignedBundle(locale: "fr", revision: 8, strings: ["greeting": textEntry("Cache fr")])
    let cachedData = try cacheBundle(cached, etag: "\"rev:8\"")
    let seed = try makeSignedBundle(locale: "fr", revision: 2, strings: ["greeting": textEntry("Seed fr")])
    try writeSeed(seed)

    let sut = makeSUT(makeConfig(locale: "en"))
    await sut.setLocale("fr")

    #expect(sut.revision == 8)
    #expect(sut["greeting"] == "Cache fr")
    #expect(loadCache(locale: "fr") == cachedData)
  }
}
