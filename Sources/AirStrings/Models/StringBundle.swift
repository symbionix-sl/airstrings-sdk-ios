struct StringBundle: Codable, Sendable {
    let formatVersion: Int
    let projectId: String
    let locale: String
    let revision: Int
    let createdAt: String
    let keyId: String
    let signature: String
    let strings: [String: String]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case projectId = "project_id"
        case locale
        case revision
        case createdAt = "created_at"
        case keyId = "key_id"
        case signature
        case strings
    }
}
