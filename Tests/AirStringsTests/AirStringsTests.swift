import XCTest
@testable import AirStrings

final class AirStringsTests: XCTestCase {

    private func makeConfig() -> AirStringsConfiguration {
        AirStringsConfiguration(
            projectId: "proj_test12345678",
            publicKeys: [:],
            locale: .fixed("en"),
            baseURL: URL(string: "https://localhost:9999")! // Will fail to connect — that's fine
        )
    }

    func testSubscriptReturnsFallbackWhenNoStrings() {
        let sut = AirStrings(configuration: makeConfig())
        XCTAssertEqual(sut["nonexistent.key"], "nonexistent.key")
        XCTAssertEqual(sut["onboarding.title"], "onboarding.title")
    }

    func testSubscriptReturnsValueWhenSet() {
        let sut = AirStrings(configuration: makeConfig())
        sut.strings = ["greeting": "Hello!", "farewell": "Goodbye!"]

        XCTAssertEqual(sut["greeting"], "Hello!")
        XCTAssertEqual(sut["farewell"], "Goodbye!")
    }

    func testSubscriptFallbackForMissingKey() {
        let sut = AirStrings(configuration: makeConfig())
        sut.strings = ["existing": "Value"]

        XCTAssertEqual(sut["existing"], "Value")
        XCTAssertEqual(sut["missing"], "missing")
    }

    func testInitialState() {
        let sut = AirStrings(configuration: makeConfig())

        XCTAssertEqual(sut.currentLocale, "en")
        XCTAssertEqual(sut.revision, 0)
        // isReady is false initially (no cache, no network)
        XCTAssertFalse(sut.isReady)
    }

    func testFixedLocaleResolution() {
        let config = AirStringsConfiguration(
            projectId: "proj_test12345678",
            publicKeys: [:],
            locale: .fixed("it"),
            baseURL: URL(string: "https://localhost:9999")!
        )
        let sut = AirStrings(configuration: config)
        XCTAssertEqual(sut.currentLocale, "it")
    }

    func testPlaceholderReturnsFallback() {
        let sut = AirStrings.placeholder
        XCTAssertEqual(sut["any.key"], "any.key")
        XCTAssertEqual(sut.revision, 0)
    }

    func testInitialRevisionIsZero() {
        let sut = AirStrings(configuration: makeConfig())
        XCTAssertEqual(sut.revision, 0)
    }

    func testStringsCanBeSetInternally() {
        let sut = AirStrings(configuration: makeConfig())
        // Internal var is accessible via @testable import
        sut.strings = ["key": "value"]
        XCTAssertEqual(sut.strings["key"], "value")
        XCTAssertEqual(sut["key"], "value")
    }
}
