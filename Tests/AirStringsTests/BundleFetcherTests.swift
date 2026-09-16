import Testing
import Foundation
import os
import SmartNet
@testable import AirStrings

@Suite("BundleFetcher")
struct BundleFetcherTests {
  let body = Data(#"{"format_version":1}"#.utf8)

  func fetch(_ fetcher: BundleFetcher, ifNoneMatch: String? = nil) async throws -> FetchResult {
    try await fetcher.fetch(
      organizationId: "org_test",
      projectId: "proj_test",
      environmentId: "env_test",
      locale: "en",
      ifNoneMatch: ifNoneMatch
    )
  }

  func refusedURL() -> URL {
    let server = LoopbackServer(.hang)
    server.stop()
    return server.url
  }

  func expectSuccess(_ result: FetchResult, data: Data) {
    guard case .success(let received, _) = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(received == data)
  }

  @Test func cdnSuccessNeverCallsFallback() async throws {
    let cdn = LoopbackServer(.respond(status: 200, headers: ["ETag": "\"rev:1\""], body: body))
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    let result = try await fetch(fetcher)

    guard case .success(let data, let etag) = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(data == body)
    #expect(etag == "\"rev:1\"")
    #expect(cdn.hits == 1)
    #expect(fallback.hits == 0)
    #expect(cdn.requests.first?.hasPrefix("GET /org_test/proj_test/env_test/en/bundle.json ") == true)
  }

  @Test func cdnHangFailsOverAfterDeadline() async throws {
    let cdn = LoopbackServer(.hang)
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url, firstAttemptTimeout: 0.3)

    let start = Date()
    let result = try await fetch(fetcher)
    let elapsed = Date().timeIntervalSince(start)

    expectSuccess(result, data: body)
    #expect(elapsed >= 0.3)
    #expect(elapsed < 3)
    #expect(fallback.hits == 1)
  }

  @Test func headersInTimeSlowBodyDoesNotFailOver() async throws {
    let slowBody = Data(repeating: 0x62, count: 1_000)
    let cdn = LoopbackServer(.respond(status: 200, body: slowBody, initialBytes: 600, bodyDelay: 1))
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url, firstAttemptTimeout: 0.3)

    let start = Date()
    let result = try await fetch(fetcher)

    expectSuccess(result, data: slowBody)
    #expect(Date().timeIntervalSince(start) >= 1)
    #expect(fallback.hits == 0)
  }

  @Test func cdnBodyDropFailsOver() async throws {
    let cdn = LoopbackServer(.dropBody)
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    let result = try await fetch(fetcher)

    expectSuccess(result, data: body)
    #expect(cdn.hits == 1)
    #expect(fallback.hits == 1)
  }

  @Test func cdnBodyDropSurfacesAsStatus200Error() async throws {
    let cdn = LoopbackServer(.dropBody)
    defer { cdn.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url)

    await #expect {
      try await fetch(fetcher)
    } throws: { error in
      guard case .error(statusCode: 200, _) = error as? NetworkError else { return false }
      return BundleFetcher.isFailoverEligible(error)
    }
  }

  @Test func cdnRefusedFailsOver() async throws {
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { fallback.stop() }
    let fetcher = BundleFetcher(baseURL: refusedURL(), fallbackURL: fallback.url)

    let result = try await fetch(fetcher)

    expectSuccess(result, data: body)
    #expect(fallback.hits == 1)
  }

  @Test func cdn5xxFailsOver() async throws {
    let cdn = LoopbackServer(.respond(status: 503))
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    let result = try await fetch(fetcher)

    expectSuccess(result, data: body)
    #expect(cdn.hits == 1)
    #expect(fallback.hits == 1)
  }

  @Test func cdn404DoesNotFailOver() async throws {
    let cdn = LoopbackServer(.respond(status: 404))
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    await #expect {
      try await fetch(fetcher)
    } throws: { error in
      guard case .error(statusCode: 404, _) = error as? NetworkError else { return false }
      return true
    }
    #expect(fallback.hits == 0)
  }

  @Test func cdn304DoesNotFailOver() async throws {
    let cdn = LoopbackServer(.respond(status: 304))
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    let result = try await fetch(fetcher, ifNoneMatch: "\"rev:1\"")

    guard case .notModified = result else {
      Issue.record("expected notModified, got \(result)")
      return
    }
    #expect(fallback.hits == 0)
  }

  @Test func noFallbackIgnoresFirstAttemptDeadline() async throws {
    let cdn = LoopbackServer(.hang)
    defer { cdn.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, firstAttemptTimeout: 0.3)
    let finished = OSAllocatedUnfairLock(initialState: false)

    let task = Task {
      defer { finished.withLock { $0 = true } }
      _ = try await fetch(fetcher)
    }
    try await Task.sleep(for: .seconds(1))
    #expect(finished.withLock { $0 } == false)

    cdn.stop()
    await #expect(throws: (any Error).self) {
      try await task.value
    }
  }

  @Test func bothHostsFailThrows() async throws {
    let cdn = LoopbackServer(.respond(status: 500))
    let fallback = LoopbackServer(.respond(status: 502))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    await #expect {
      try await fetch(fetcher)
    } throws: { error in
      guard case .error(statusCode: 502, _) = error as? NetworkError else { return false }
      return true
    }
    #expect(cdn.hits == 1)
    #expect(fallback.hits == 1)
  }

  @Test func stickyAfterFailover() async throws {
    let cdn = LoopbackServer(.respond(status: 503))
    let fallback = LoopbackServer(.respond(status: 200, body: body))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url, firstAttemptTimeout: 0.3)

    expectSuccess(try await fetch(fetcher), data: body)
    let start = Date()
    expectSuccess(try await fetch(fetcher), data: body)

    #expect(Date().timeIntervalSince(start) < 0.3)
    #expect(cdn.hits == 1)
    #expect(fallback.hits == 2)
  }

  @Test func ifNoneMatchSentToFallbackAnd304Handled() async throws {
    let cdn = LoopbackServer(.respond(status: 503))
    let fallback = LoopbackServer(.respond(status: 304))
    defer { cdn.stop(); fallback.stop() }
    let fetcher = BundleFetcher(baseURL: cdn.url, fallbackURL: fallback.url)

    let result = try await fetch(fetcher, ifNoneMatch: "\"rev:7\"")

    guard case .notModified = result else {
      Issue.record("expected notModified, got \(result)")
      return
    }
    for head in cdn.requests + fallback.requests {
      #expect(head.lowercased().contains("if-none-match: \"rev:7\"\r\n"))
    }
    #expect(fallback.hits == 1)
  }

  @Test func failoverEligibility() {
    #expect(BundleFetcher.isFailoverEligible(NetworkError.timeout))
    #expect(BundleFetcher.isFailoverEligible(NetworkError.error(statusCode: 500, data: nil)))
    #expect(BundleFetcher.isFailoverEligible(URLError(.cannotConnectToHost)))
    #expect(!BundleFetcher.isFailoverEligible(NetworkError.error(statusCode: 404, data: nil)))
    #expect(!BundleFetcher.isFailoverEligible(NetworkError.error(statusCode: 304, data: nil)))
    #expect(!BundleFetcher.isFailoverEligible(NetworkError.rateLimited(retryAfter: nil)))
    #expect(!BundleFetcher.isFailoverEligible(NetworkError.cancelled))
    #expect(!BundleFetcher.isFailoverEligible(NetworkError.parsingFailed()))
    #expect(!BundleFetcher.isFailoverEligible(CocoaError(.coderReadCorrupt)))
  }
}
