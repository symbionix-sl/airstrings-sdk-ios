import Testing
import Foundation
@testable import AirStrings

@Suite(
  "LiveFailoverE2E",
  .enabled(if: ProcessInfo.processInfo.environment["AIRSTRINGS_LIVE_E2E"] == "1"),
  .timeLimit(.minutes(1))
)
@MainActor
final class LiveFailoverE2ETests {
  private let root: URL
  private let store: BundleStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AirStringsLiveE2E-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = BundleStore(baseDirectory: root.appendingPathComponent("store", isDirectory: true))
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  private func env(_ name: String) throws -> String {
    try #require(ProcessInfo.processInfo.environment["AIRSTRINGS_E2E_\(name)"], "AIRSTRINGS_E2E_\(name) is not set")
  }

  @Test func failsOverToFallbackAndStaysThere() async throws {
    let hangingCDN = LoopbackServer(.hang)
    let cdn = ProcessInfo.processInfo.environment["AIRSTRINGS_E2E_CDN_BASE"] ?? hangingCDN.url.absoluteString
    let api = LoopbackServer(.respond(status: 200, body: try JSONSerialization.data(withJSONObject: [
      "cdn_base_url": cdn,
      "fallback_base_url": try env("FALLBACK_BASE"),
    ])))
    defer { hangingCDN.stop(); api.stop() }

    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
    let start = ContinuousClock.now
    let sut = AirStrings(
      configuration: AirStringsConfiguration(
        organizationId: try env("ORG"),
        projectId: try env("PROJ"),
        environmentId: try env("ENV"),
        publicKeys: [try env("PUBLIC_KEY")],
        locale: .fixed(try env("LOCALE")),
        apiBaseURL: api.url,
        isSeedingEnabled: false
      ),
      store: store
    )
    await sut.refresh()
    let firstLoad = start.duration(to: .now)
    print("LiveFailoverE2E cdn=\(cdn) firstLoad=\(firstLoad) ready=\(sut.isReady) revision=\(sut.revision)")

    #expect(sut.isReady)
    #expect(sut.revision > 0)
    #expect(firstLoad >= .seconds(5))
    #expect(firstLoad <= .seconds(12))

    let secondStart = ContinuousClock.now
    await sut.refresh()
    let secondLoad = secondStart.duration(to: .now)
    print("LiveFailoverE2E secondLoad=\(secondLoad) revision=\(sut.revision)")

    #expect(secondLoad < .seconds(2))
    #expect(sut.isReady)
  }
}
