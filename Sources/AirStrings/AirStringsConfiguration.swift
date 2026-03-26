import Foundation

public struct AirStringsConfiguration: Sendable {
  public let organizationId: String
  public let projectId: String
  public let environmentId: String
  public let publicKeys: [String]
  public let locale: AirStringsLocale
  public let apiBaseURL: URL
  var baseURL: URL?

  public init(
    organizationId: String,
    projectId: String,
    environmentId: String,
    publicKeys: [String],
    locale: AirStringsLocale = .system,
    apiBaseURL: URL = URL(string: "https://api.airstrings.com")!
  ) {
    self.organizationId = organizationId
    self.projectId = projectId
    self.environmentId = environmentId
    self.publicKeys = publicKeys
    self.locale = locale
    self.apiBaseURL = apiBaseURL
    self.baseURL = nil
  }

  /// Internal initializer for testing and local development.
  init(
    organizationId: String,
    projectId: String,
    environmentId: String,
    publicKeys: [String],
    locale: AirStringsLocale = .system,
    baseURL: URL
  ) {
    self.organizationId = organizationId
    self.projectId = projectId
    self.environmentId = environmentId
    self.publicKeys = publicKeys
    self.locale = locale
    self.apiBaseURL = baseURL
    self.baseURL = baseURL
  }

  static let placeholder = AirStringsConfiguration(
    organizationId: "",
    projectId: "",
    environmentId: "",
    publicKeys: [],
    locale: .fixed("en"),
    baseURL: URL(string: "https://localhost")!
  )
}
