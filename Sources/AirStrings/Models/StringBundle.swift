struct Experiment: Codable, Sendable, Equatable {
  let id: String
  let allocation: [String: Int]
  let variants: [String: String]
}

struct StringEntry: Codable, Sendable, Equatable {
  let value: String
  let format: StringFormat
  let experiment: Experiment?

  enum StringFormat: String, Codable, Sendable {
    case text
    case icu
  }

  enum CodingKeys: String, CodingKey {
    case value
    case format
    case experiment
  }

  init(value: String, format: StringFormat, experiment: Experiment? = nil) {
    self.value = value
    self.format = format
    self.experiment = experiment
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    value = try container.decode(String.self, forKey: .value)
    format = try container.decode(StringFormat.self, forKey: .format)
    experiment = try? container.decode(Experiment.self, forKey: .experiment)
  }
}

struct StringBundle: Codable, Sendable {
  let formatVersion: Int
  let projectId: String
  let locale: String
  let revision: Int
  let createdAt: String
  let keyId: String
  let signature: String
  let strings: [String: StringEntry]
  let experimentsSignature: String?

  init(
    formatVersion: Int,
    projectId: String,
    locale: String,
    revision: Int,
    createdAt: String,
    keyId: String,
    signature: String,
    strings: [String: StringEntry],
    experimentsSignature: String? = nil
  ) {
    self.formatVersion = formatVersion
    self.projectId = projectId
    self.locale = locale
    self.revision = revision
    self.createdAt = createdAt
    self.keyId = keyId
    self.signature = signature
    self.strings = strings
    self.experimentsSignature = experimentsSignature
  }

  enum CodingKeys: String, CodingKey {
    case formatVersion = "format_version"
    case projectId = "project_id"
    case locale
    case revision
    case createdAt = "created_at"
    case keyId = "key_id"
    case signature
    case strings
    case experimentsSignature = "experiments_signature"
  }
}
