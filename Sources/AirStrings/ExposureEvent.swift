public struct ExposureEvent: Sendable, Equatable {
  public let key: String
  public let experimentId: String
  public let variant: String
  public let locale: String
  public let assignmentId: String

  public init(
    key: String,
    experimentId: String,
    variant: String,
    locale: String,
    assignmentId: String
  ) {
    self.key = key
    self.experimentId = experimentId
    self.variant = variant
    self.locale = locale
    self.assignmentId = assignmentId
  }
}
