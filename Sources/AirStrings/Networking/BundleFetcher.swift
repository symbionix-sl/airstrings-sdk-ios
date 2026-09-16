import Foundation
import os
import SmartNet

enum FetchResult: Sendable {
  case success(data: Data, etag: String?)
  case notModified
}

final class BundleFetcher: @unchecked Sendable {
  private let lock = NSLock()
  private var clients: [ApiClient]
  private let firstAttemptTimeout: TimeInterval
  private let logger = Logger(subsystem: "com.airstrings.sdk", category: "BundleFetcher")

  init(baseURL: URL, fallbackURL: URL? = nil, firstAttemptTimeout: TimeInterval = 5) {
    self.clients = [baseURL, fallbackURL].compactMap { url in
      url.map {
        ApiClient(config: NetworkConfiguration(
          baseURL: $0,
          requestTimeout: 30,
          debug: false
        ))
      }
    }
    self.firstAttemptTimeout = firstAttemptTimeout
  }

  func fetch(
    organizationId: String,
    projectId: String,
    environmentId: String,
    locale: String,
    ifNoneMatch: String? = nil
  ) async throws -> FetchResult {
    var endpoint = Endpoint<Data>.get("\(organizationId)/\(projectId)/\(environmentId)/\(locale)/bundle.json")

    if let etag = ifNoneMatch {
      endpoint = endpoint.header("If-None-Match", etag)
    }

    let hosts = lock.withLock { clients }
    guard hosts.count > 1 else {
      return try await attempt(hosts[0], endpoint: endpoint, deadline: nil)
    }

    do {
      return try await attempt(hosts[0], endpoint: endpoint, deadline: firstAttemptTimeout)
    } catch where Self.isFailoverEligible(error) {
      logger.warning("Bundle fetch from \(hosts[0].config.baseURL.host() ?? "", privacy: .public) failed, retrying on \(hosts[1].config.baseURL.host() ?? "", privacy: .public)")
      let result = try await attempt(hosts[1], endpoint: endpoint, deadline: nil)
      lock.withLock { clients = [hosts[1], hosts[0]] }
      return result
    }
  }

  static func isFailoverEligible(_ error: any Error) -> Bool {
    if error is URLError { return true }
    switch error as? NetworkError {
    case .timeout, .networkFailure, .dnsLookupFailed, .connectionLost, .sslError, .generic:
      return true
    case .error(let statusCode, _):
      return (500...599).contains(statusCode) || (200...299).contains(statusCode)
    default:
      return false
    }
  }

  private func attempt(_ client: ApiClient, endpoint: Endpoint<Data>, deadline: TimeInterval?) async throws -> FetchResult {
    let timedOut = OSAllocatedUnfairLock(initialState: false)
    return try await withCheckedThrowingContinuation { continuation in
      let task = client.request(with: endpoint) { (response: Response<Data>) in
        // SmartNet treats 304 as error (non-2xx). Intercept before result check.
        if response.statusCode == 304 {
          continuation.resume(returning: .notModified)
          return
        }

        switch response.result {
        case .success(let data):
          let etag = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "ETag")
          continuation.resume(returning: .success(data: data, etag: etag))
        case .failure(.cancelled) where timedOut.withLock({ $0 }):
          continuation.resume(throwing: NetworkError.timeout)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }

      guard let deadline, let task = task as? URLSessionTask else { return }
      DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
        guard task.response == nil else { return }
        timedOut.withLock { $0 = true }
        task.cancel()
      }
    }
  }
}
