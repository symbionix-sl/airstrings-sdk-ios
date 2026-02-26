import Foundation

public struct AirStringsConfiguration: Sendable {
    public let projectId: String
    public let publicKeys: [String: Data]
    public let locale: AirStringsLocale
    public let baseURL: URL

    public init(
        projectId: String,
        publicKeys: [String: Data],
        locale: AirStringsLocale = .system,
        baseURL: URL = URL(string: "https://cdn.airstrings.com")!
    ) {
        self.projectId = projectId
        self.publicKeys = publicKeys
        self.locale = locale
        self.baseURL = baseURL
    }

    static let placeholder = AirStringsConfiguration(
        projectId: "",
        publicKeys: [:],
        locale: .fixed("en"),
        baseURL: URL(string: "https://localhost")!
    )
}
