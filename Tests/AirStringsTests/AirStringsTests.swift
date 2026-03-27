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
