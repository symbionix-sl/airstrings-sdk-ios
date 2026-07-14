import CryptoKit
import Testing
import Foundation
@testable import AirStrings

@Suite("AirStrings")
@MainActor
struct AirStringsTests {

  private func makeConfig() -> AirStringsConfiguration {
    AirStringsConfiguration(
      organizationId: "org_test12345678",
      projectId: "proj_test12345678",
      environmentId: "env_test12345678",
      publicKeys: [],
      locale: .fixed("en"),
      baseURL: URL(string: "https://localhost:9999")!
    )
  }

  @Test func subscriptReturnsFallbackWhenNoStrings() {
    let sut = AirStrings(configuration: makeConfig())
    #expect(sut["nonexistent.key"] == "nonexistent.key")
    #expect(sut["onboarding.title"] == "onboarding.title")
  }

  @Test func subscriptReturnsValueWhenSet() {
    let sut = AirStrings(configuration: makeConfig())
    sut.strings = ["greeting": "Hello!", "farewell": "Goodbye!"]
    #expect(sut["greeting"] == "Hello!")
    #expect(sut["farewell"] == "Goodbye!")
  }

  @Test func subscriptFallbackForMissingKey() {
    let sut = AirStrings(configuration: makeConfig())
    sut.strings = ["existing": "Value"]
    #expect(sut["existing"] == "Value")
    #expect(sut["missing"] == "missing")
  }

  @Test func initialState() {
    let sut = AirStrings(configuration: makeConfig())
    #expect(sut.currentLocale == "en")
    #expect(sut.revision == 0)
    #expect(!sut.isReady)
  }

  @Test func fixedLocaleResolution() {
    let config = AirStringsConfiguration(
      organizationId: "org_test12345678",
      projectId: "proj_test12345678",
      environmentId: "env_test12345678",
      publicKeys: [],
      locale: .fixed("it"),
      baseURL: URL(string: "https://localhost:9999")!
    )
    let sut = AirStrings(configuration: config)
    #expect(sut.currentLocale == "it")
  }

  @Test func placeholderReturnsFallback() {
    let sut = AirStrings.placeholder
    #expect(sut["any.key"] == "any.key")
    #expect(sut.revision == 0)
  }

  @Test func initialRevisionIsZero() {
    let sut = AirStrings(configuration: makeConfig())
    #expect(sut.revision == 0)
  }

  @Test func stringsCanBeSetInternally() {
    let sut = AirStrings(configuration: makeConfig())
    sut.strings = ["key": "value"]
    #expect(sut.strings["key"] == "value")
    #expect(sut["key"] == "value")
  }

  // MARK: - ICU formatting via string(_:args:)

  @Test func stringMethodReturnsKeyFallbackWhenNoStrings() {
    let sut = AirStrings(configuration: makeConfig())
    #expect(sut.string("missing.key", args: [:]) == "missing.key")
  }

  @Test func stringMethodReturnsTextValueIgnoringArgs() {
    let sut = AirStrings(configuration: makeConfig())
    sut.stringEntries = [
      "greeting": StringEntry(value: "Hello!", format: .text)
    ]
    sut.strings = ["greeting": "Hello!"]
    #expect(sut.string("greeting", args: ["name": "World"]) == "Hello!")
  }

  @Test func stringMethodFormatsICUPlural() {
    let sut = AirStrings(configuration: makeConfig())
    sut.stringEntries = [
      "items.count": StringEntry(
        value: "{count, plural, one {# item} other {# items}}",
        format: .icu
      )
    ]
    sut.strings = ["items.count": "{count, plural, one {# item} other {# items}}"]

    #expect(sut.string("items.count", args: ["count": 1]) == "1 item")
    #expect(sut.string("items.count", args: ["count": 5]) == "5 items")
    #expect(sut.string("items.count", args: ["count": 0]) == "0 items")
  }

  @Test func stringMethodFormatsICUSelect() {
    let sut = AirStrings(configuration: makeConfig())
    sut.stringEntries = [
      "pronoun": StringEntry(
        value: "{gender, select, male {He} female {She} other {They}}",
        format: .icu
      )
    ]
    sut.strings = ["pronoun": "{gender, select, male {He} female {She} other {They}}"]

    #expect(sut.string("pronoun", args: ["gender": "male"]) == "He")
    #expect(sut.string("pronoun", args: ["gender": "female"]) == "She")
    #expect(sut.string("pronoun", args: ["gender": "nonbinary"]) == "They")
  }

  @Test func stringMethodReturnsRawPatternOnFormattingFailure() {
    let sut = AirStrings(configuration: makeConfig())
    let pattern = "{missing_arg, plural, one {# item} other {# items}}"
    sut.stringEntries = [
      "broken": StringEntry(value: pattern, format: .icu)
    ]
    sut.strings = ["broken": pattern]

    // Missing argument → returns raw pattern
    #expect(sut.string("broken", args: ["wrong_arg": 1]) == pattern)
  }

  // MARK: - Locale switch: previous strings retained

  @Test func setLocaleKeepsPreviousStringsWhenNoCacheExists() async {
    let sut = AirStrings(configuration: makeConfig())
    sut.strings = ["title": "Hello", "subtitle": "World"]
    sut.stringEntries = [
      "title": StringEntry(value: "Hello", format: .text),
      "subtitle": StringEntry(value: "World", format: .text),
    ]

    // Switch to a locale with no cached bundle — network will fail (localhost:9999)
    await sut.setLocale("fr")

    // Previous strings must still be accessible, not cleared to empty
    #expect(sut["title"] == "Hello")
    #expect(sut["subtitle"] == "World")
    #expect(sut.strings.isEmpty == false)
  }

  @Test func setLocaleKeepsStringEntriesWhenNoCacheExists() async {
    let sut = AirStrings(configuration: makeConfig())
    sut.strings = ["greeting": "Hola"]
    sut.stringEntries = [
      "greeting": StringEntry(value: "Hola", format: .text),
    ]

    await sut.setLocale("de")

    // string(_:args:) should still work with previous entries
    #expect(sut.string("greeting", args: [:]) == "Hola")
  }

  @Test func setLocaleUpdatesCurrentLocaleImmediately() async {
    let sut = AirStrings(configuration: makeConfig())
    sut.strings = ["key": "value"]

    await sut.setLocale("ja")

    #expect(sut.currentLocale == "ja")
    // And strings are still there
    #expect(sut["key"] == "value")
  }

  @Test func stringMethodSimpleSubstitution() {
    let sut = AirStrings(configuration: makeConfig())
    sut.stringEntries = [
      "hello": StringEntry(value: "Hello, {name}!", format: .icu)
    ]
    sut.strings = ["hello": "Hello, {name}!"]

    #expect(sut.string("hello", args: ["name": "Alice"]) == "Hello, Alice!")
  }
}

@Suite("AirStringsExperiments")
@MainActor
final class AirStringsExperimentsTests {
  private let root: URL
  private let appDir: URL
  private let seedDir: URL
  private let store: BundleStore
  private let privateKey: Curve25519.Signing.PrivateKey
  private var exposures: [ExposureEvent] = []
  private var stringsUpdatedCount = 0

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AirStringsExpTests-\(UUID().uuidString)", isDirectory: true)
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

  private enum ExperimentsSig {
    case valid
    case tampered
    case absent
  }

  private func ctaEntry() -> StringEntry {
    StringEntry(
      value: "Continue",
      format: .text,
      experiment: Experiment(
        id: "exp_checkout_cta",
        allocation: ["control": 50, "variant_a": 50],
        variants: ["variant_a": "Variant A CTA"]
      )
    )
  }

  private func makeSignedBundle(
    projectId: String = "proj_test12345678",
    locale: String = "en",
    revision: Int,
    strings: [String: StringEntry],
    experimentsSig: ExperimentsSig = .valid
  ) throws -> StringBundle {
    let createdAt = "2026-07-14T10:00:00Z"
    let unsigned = StringBundle(
      formatVersion: 1, projectId: projectId, locale: locale, revision: revision,
      createdAt: createdAt, keyId: keyBase64, signature: "", strings: strings
    )
    let baseSig = Base64URL.encode(try privateKey.signature(for: CanonicalJSON.signedContent(from: unsigned)))
    let expSig: String?
    switch experimentsSig {
    case .valid:
      expSig = Base64URL.encode(try privateKey.signature(for: CanonicalJSON.experimentsSignedContent(from: unsigned)))
    case .tampered:
      expSig = Base64URL.encode(try privateKey.signature(for: Data("tampered-experiments".utf8)))
    case .absent:
      expSig = nil
    }
    return StringBundle(
      formatVersion: 1, projectId: projectId, locale: locale, revision: revision,
      createdAt: createdAt, keyId: keyBase64, signature: baseSig, strings: strings,
      experimentsSignature: expSig
    )
  }

  @discardableResult
  private func writeSeed(_ bundle: StringBundle) throws -> Data {
    let data = try JSONEncoder().encode(bundle)
    try data.write(to: seedDir.appendingPathComponent("\(bundle.locale).json"))
    return data
  }

  @discardableResult
  private func cacheBundle(_ bundle: StringBundle, etag: String? = nil) throws -> Data {
    let data = try JSONEncoder().encode(bundle)
    store.save(data, projectId: "proj_test12345678", environmentId: "env_test12345678", locale: bundle.locale, etag: etag)
    return data
  }

  private func makeConfig(locale: String = "en") -> AirStringsConfiguration {
    AirStringsConfiguration(
      organizationId: "org_test12345678",
      projectId: "proj_test12345678",
      environmentId: "env_test12345678",
      publicKeys: [keyBase64],
      locale: .fixed(locale),
      baseURL: URL(string: "https://localhost:9999")!,
      seedBundle: Bundle(url: appDir)!
    )
  }

  private func makeSUT(_ configuration: AirStringsConfiguration? = nil) -> AirStrings {
    let sut = AirStrings(configuration: configuration ?? makeConfig(), store: store)
    sut.onExposure = { [weak self] event in self?.exposures.append(event) }
    sut.onStringsUpdated = { [weak self] _, _ in self?.stringsUpdatedCount += 1 }
    return sut
  }

  private func flush() async {
    for _ in 0..<5 { await Task.yield() }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }

  @Test func signedExperimentsWithAssignmentServesVariantValue() throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()
    #expect(sut["checkout.cta"] == "Continue")

    sut.setAssignmentId("user_1")
    #expect(sut["checkout.cta"] == "Variant A CTA")
    #expect(sut.string("checkout.cta", args: [:]) == "Variant A CTA")
  }

  @Test func noAssignmentServesBaseWithoutExposure() async throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()

    #expect(sut["checkout.cta"] == "Continue")
    await flush()
    #expect(exposures.isEmpty)
    #expect(sut.isReady)
    #expect(sut.revision == 3)
  }

  @Test func tamperedExperimentsSignatureServesBaseButAppliesBundle() async throws {
    try writeSeed(try makeSignedBundle(revision: 5, strings: ["checkout.cta": ctaEntry()], experimentsSig: .tampered))
    let sut = makeSUT()

    sut.setAssignmentId("user_1")
    #expect(sut["checkout.cta"] == "Continue")
    #expect(sut.isReady)
    #expect(sut.revision == 5)
    await flush()
    #expect(exposures.isEmpty)
  }

  @Test func absentExperimentsSignatureServesBase() async throws {
    try writeSeed(try makeSignedBundle(revision: 5, strings: ["checkout.cta": ctaEntry()], experimentsSig: .absent))
    let sut = makeSUT()

    sut.setAssignmentId("user_1")
    #expect(sut["checkout.cta"] == "Continue")
    #expect(sut.isReady)
    await flush()
    #expect(exposures.isEmpty)
  }

  @Test func exactlyOneVariantExposureDedupedAcrossReads() async throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()
    sut.setAssignmentId("user_1")

    _ = sut["checkout.cta"]
    _ = sut["checkout.cta"]
    _ = sut.string("checkout.cta", args: [:])
    await flush()

    #expect(exposures.count == 1)
    let event = try #require(exposures.first)
    #expect(event.key == "checkout.cta")
    #expect(event.experimentId == "exp_checkout_cta")
    #expect(event.variant == "variant_a")
    #expect(event.assignmentId == "user_1")
    #expect(event.locale == "en")
  }

  @Test func exposureDedupedAcrossReappliedBundles() async throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()
    sut.setAssignmentId("user_1")

    _ = sut["checkout.cta"]
    await flush()
    #expect(exposures.count == 1)

    await sut.setLocale("en")
    _ = sut["checkout.cta"]
    await flush()

    #expect(exposures.count == 1)
    #expect(sut["checkout.cta"] == "Variant A CTA")
  }

  @Test func controlExposureRecordedAsControl() async throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()
    sut.setAssignmentId("user_2")

    #expect(sut["checkout.cta"] == "Continue")
    await flush()

    #expect(exposures.count == 1)
    let event = try #require(exposures.first)
    #expect(event.variant == "control")
    #expect(event.experimentId == "exp_checkout_cta")
    #expect(event.key == "checkout.cta")
    #expect(event.assignmentId == "user_2")
  }

  @Test func preVariantsBundleBehavesAsBefore() async throws {
    try writeSeed(try makeSignedBundle(
      revision: 4,
      strings: ["greeting": StringEntry(value: "Hello", format: .text)],
      experimentsSig: .absent
    ))
    let sut = makeSUT()
    sut.setAssignmentId("user_1")

    #expect(sut["greeting"] == "Hello")
    #expect(sut.string("greeting", args: [:]) == "Hello")
    #expect(sut.isReady)
    #expect(sut.revision == 4)
    await flush()
    #expect(exposures.isEmpty)
  }

  @Test func setAssignmentIdSwitchesServedValueAndNotifies() throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()
    #expect(sut["checkout.cta"] == "Continue")

    stringsUpdatedCount = 0
    sut.setAssignmentId("user_1")
    #expect(sut["checkout.cta"] == "Variant A CTA")
    #expect(stringsUpdatedCount == 1)

    sut.setAssignmentId(nil)
    #expect(sut["checkout.cta"] == "Continue")
    #expect(stringsUpdatedCount == 2)
  }

  @Test func seedLoadPathServesVariants() throws {
    try writeSeed(try makeSignedBundle(revision: 3, strings: ["checkout.cta": ctaEntry()]))
    let sut = makeSUT()
    sut.setAssignmentId("user_1")
    #expect(sut["checkout.cta"] == "Variant A CTA")
    #expect(sut.revision == 3)
  }

  @Test func cacheLoadPathServesVariants() throws {
    try cacheBundle(try makeSignedBundle(revision: 6, strings: ["checkout.cta": ctaEntry()]), etag: "\"rev:6\"")
    let sut = makeSUT()
    sut.setAssignmentId("user_1")
    #expect(sut["checkout.cta"] == "Variant A CTA")
    #expect(sut.revision == 6)
  }
}
