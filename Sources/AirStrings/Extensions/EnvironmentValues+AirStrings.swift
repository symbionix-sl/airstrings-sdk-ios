import SwiftUI

private struct AirStringsKey: EnvironmentKey {
  static let defaultValue = AirStrings.placeholder
}

extension EnvironmentValues {
  public var airStrings: AirStrings {
    get { self[AirStringsKey.self] }
    set { self[AirStringsKey.self] = newValue }
  }
}
