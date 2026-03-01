import Foundation
import SmartNet

enum FetchResult: Sendable {
  case success(data: Data, etag: String?)
  case notModified
}

final class BundleFetcher: @unchecked Sendable {
  private let client: ApiClient
  
  init(baseURL: URL) {
    #if DEBUG
    let debug = true
    #else
    let debug = false
    #endif
    let config = NetworkConfiguration(
      baseURL: baseURL,
      requestTimeout: 30,
      debug: debug
    )
    self.client = ApiClient(config: config)
  }
  
  func fetch(
    projectId: String,
    locale: String,
    ifNoneMatch: String? = nil
  ) async throws -> FetchResult {
    var endpoint = Endpoint<Data>.get("v1/\(projectId)/\(locale)/bundle.json")
    
    if let etag = ifNoneMatch {
      endpoint = endpoint.header("If-None-Match", etag)
    }
    
    return try await withCheckedThrowingContinuation { continuation in
      _ = client.request(with: endpoint) { (response: Response<Data>) in
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
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
