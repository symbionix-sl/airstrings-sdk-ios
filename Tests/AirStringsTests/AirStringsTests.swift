import Testing
import Foundation
@testable import AirStrings

@Suite("AirStrings")
@MainActor
struct AirStringsTests {

  private func makeConfig() -> AirStringsConfiguration {
    AirStringsConfiguration(
      projectId: "proj_test12345678",
      publicKeys: [:],
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
      projectId: "proj_test12345678",
      publicKeys: [:],
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
}
