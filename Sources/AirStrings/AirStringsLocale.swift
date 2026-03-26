import Foundation

public enum AirStringsLocale: Sendable {
  /// Uses the device's current locale, mapped to a BCP 47 language tag.
  case system

  /// Always uses the specified BCP 47 locale regardless of device settings.
  case fixed(String)

  var resolved: String {
    switch self {
    case .system:
      return Locale.current.language.languageCode?.identifier ?? "en"
    case .fixed(let bcp47):
      return bcp47
    }
  }
}
