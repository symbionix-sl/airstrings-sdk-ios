import Foundation

/// Lightweight ICU MessageFormat formatter for runtime pattern formatting.
///
/// Supports:
/// - Simple argument substitution: `{name}` → value of "name"
/// - Plural: `{count, plural, one {# item} other {# items}}`
/// - Select: `{gender, select, male {He} female {She} other {They}}`
///
/// Returns the raw pattern on any parse/format failure (never crashes).
enum ICUMessageFormat {
  /// Formats an ICU MessageFormat pattern with the given arguments.
  /// Returns the raw pattern if formatting fails.
  static func format(_ pattern: String, locale: String, args: [String: Any]) -> String {
    do {
      return try formatImpl(pattern, locale: locale, args: args)
    } catch {
      return pattern
    }
  }

  private static func formatImpl(
    _ pattern: String,
    locale: String,
    args: [String: Any]
  ) throws -> String {
    var result = ""
    var index = pattern.startIndex

    while index < pattern.endIndex {
      let ch = pattern[index]

      if ch == "'" {
        // ICU quoting: '' → literal ', 'text' → literal text
        let next = pattern.index(after: index)
        if next < pattern.endIndex && pattern[next] == "'" {
          result.append("'")
          index = pattern.index(after: next)
        } else if let closeQuote = pattern[next...].firstIndex(of: "'"), closeQuote > next {
          result.append(contentsOf: pattern[next..<closeQuote])
          index = pattern.index(after: closeQuote)
        } else {
          result.append(ch)
          index = next
        }
      } else if ch == "{" {
        let (replacement, afterBrace) = try parsePlaceholder(
          pattern, from: index, locale: locale, args: args
        )
        result.append(replacement)
        index = afterBrace
      } else {
        result.append(ch)
        index = pattern.index(after: index)
      }
    }

    return result
  }

  private static func parsePlaceholder(
    _ pattern: String,
    from start: String.Index,
    locale: String,
    args: [String: Any]
  ) throws -> (String, String.Index) {
    // Find matching closing brace, respecting nesting
    guard let contentRange = findBraceContent(pattern, from: start) else {
      throw FormatError.unmatchedBrace
    }

    let content = String(pattern[contentRange.content])
    let afterBrace = contentRange.afterClose

    // Split on first comma to determine type
    let parts = splitTopLevel(content, separator: ",", maxSplits: 2)
    let argName = parts[0].trimmingCharacters(in: .whitespaces)

    guard let argValue = args[argName] else {
      throw FormatError.missingArgument(argName)
    }

    if parts.count == 1 {
      // Simple substitution: {name}
      return (stringValue(argValue), afterBrace)
    }

    let type = parts[1].trimmingCharacters(in: .whitespaces)

    switch type {
    case "plural":
      guard parts.count == 3 else { throw FormatError.invalidFormat }
      let formatted = try formatPlural(
        choices: parts[2],
        value: numericValue(argValue),
        locale: locale,
        args: args
      )
      return (formatted, afterBrace)

    case "select":
      guard parts.count == 3 else { throw FormatError.invalidFormat }
      let formatted = try formatSelect(
        choices: parts[2],
        value: stringValue(argValue),
        locale: locale,
        args: args
      )
      return (formatted, afterBrace)

    default:
      // Unknown type — return the raw value
      return (stringValue(argValue), afterBrace)
    }
  }

  // MARK: - Plural

  private static func formatPlural(
    choices: String,
    value: Double,
    locale: String,
    args: [String: Any]
  ) throws -> String {
    let parsed = parseChoices(choices.trimmingCharacters(in: .whitespaces))

    // Check for exact match first (=0, =1, etc.)
    let exactKey = "=\(Int(value))"
    if let pattern = parsed[exactKey] {
      return replaceHash(
        try formatImpl(pattern, locale: locale, args: args),
        with: value,
        locale: locale
      )
    }

    // Then check CLDR plural category
    let category = pluralCategory(for: value, locale: locale)
    if let pattern = parsed[category] {
      return replaceHash(
        try formatImpl(pattern, locale: locale, args: args),
        with: value,
        locale: locale
      )
    }

    // Fall back to "other"
    if let pattern = parsed["other"] {
      return replaceHash(
        try formatImpl(pattern, locale: locale, args: args),
        with: value,
        locale: locale
      )
    }

    throw FormatError.noPluralMatch
  }

  // MARK: - Select

  private static func formatSelect(
    choices: String,
    value: String,
    locale: String,
    args: [String: Any]
  ) throws -> String {
    let parsed = parseChoices(choices.trimmingCharacters(in: .whitespaces))

    if let pattern = parsed[value] {
      return try formatImpl(pattern, locale: locale, args: args)
    }

    if let pattern = parsed["other"] {
      return try formatImpl(pattern, locale: locale, args: args)
    }

    throw FormatError.noSelectMatch
  }

  // MARK: - Choice parsing

  /// Parses `one {# item} other {# items}` into `["one": "# item", "other": "# items"]`
  private static func parseChoices(_ input: String) -> [String: String] {
    var result: [String: String] = [:]
    var index = input.startIndex

    while index < input.endIndex {
      // Skip whitespace
      while index < input.endIndex && input[index].isWhitespace {
        index = input.index(after: index)
      }
      guard index < input.endIndex else { break }

      // Read keyword (until whitespace or '{')
      var keyword = ""
      while index < input.endIndex && !input[index].isWhitespace && input[index] != "{" {
        keyword.append(input[index])
        index = input.index(after: index)
      }

      // Skip whitespace
      while index < input.endIndex && input[index].isWhitespace {
        index = input.index(after: index)
      }

      guard index < input.endIndex && input[index] == "{" else { break }

      // Find matching close brace
      guard let braceContent = findBraceContent(input, from: index) else { break }
      result[keyword] = String(input[braceContent.content])
      index = braceContent.afterClose
    }

    return result
  }

  // MARK: - Brace matching

  private struct BraceContent {
    let content: Range<String.Index>
    let afterClose: String.Index
  }

  private static func findBraceContent(
    _ s: String,
    from start: String.Index
  ) -> BraceContent? {
    guard start < s.endIndex && s[start] == "{" else { return nil }

    let contentStart = s.index(after: start)
    var depth = 1
    var index = contentStart

    while index < s.endIndex && depth > 0 {
      switch s[index] {
      case "{": depth += 1
      case "}": depth -= 1
      case "'":
        // Skip quoted content
        let next = s.index(after: index)
        if next < s.endIndex {
          if s[next] == "'" {
            index = next
          } else if let closeQuote = s[next...].firstIndex(of: "'") {
            index = closeQuote
          }
        }
      default: break
      }
      if depth > 0 {
        index = s.index(after: index)
      }
    }

    guard depth == 0 else { return nil }

    let contentEnd = index
    let afterClose = s.index(after: index)

    return BraceContent(
      content: contentStart..<contentEnd,
      afterClose: afterClose
    )
  }

  // MARK: - Plural categories

  private static func pluralCategory(for value: Double, locale: String) -> String {
    // Use Foundation's plural rules
    let rule = Self.pluralRule(for: value, locale: locale)
    return rule
  }

  private static func pluralRule(for number: Double, locale: String) -> String {
    // Foundation exposes CLDR plural rules through NumberFormatter + localized strings.
    // For common locales, the rules are well-defined. We use a simplified but
    // correct implementation covering the CLDR plural categories.
    let n = abs(number)
    let i = Int(n) // integer part
    let langCode = Locale(identifier: locale).language.languageCode?.identifier ?? "en"

    switch langCode {
    // English, German, Dutch, etc.: one if i=1 and no visible fraction
    case "en", "de", "nl", "sv", "da", "no", "nb", "nn", "it", "es", "pt", "el", "fi",
         "bg", "et", "hu", "lb", "tr":
      if i == 1 && n == Double(i) { return "one" }
      return "other"

    // French, Brazilian Portuguese: one if i=0 or i=1
    case "fr":
      if i == 0 || i == 1 { return "one" }
      return "other"

    // Arabic: complex rules
    case "ar":
      if n == 0 { return "zero" }
      if n == 1 { return "one" }
      if n == 2 { return "two" }
      let mod100 = i % 100
      if mod100 >= 3 && mod100 <= 10 { return "few" }
      if mod100 >= 11 && mod100 <= 99 { return "many" }
      return "other"

    // Russian, Ukrainian, etc.
    case "ru", "uk", "hr", "sr", "bs":
      let mod10 = i % 10
      let mod100 = i % 100
      if mod10 == 1 && mod100 != 11 { return "one" }
      if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return "few" }
      return "other"

    // Polish
    case "pl":
      if i == 1 { return "one" }
      let mod10 = i % 10
      let mod100 = i % 100
      if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return "few" }
      return "other"

    // Japanese, Chinese, Korean, Thai, Vietnamese: no plural forms
    case "ja", "zh", "ko", "th", "vi", "id", "ms":
      return "other"

    default:
      // Default English-like rule
      if i == 1 && n == Double(i) { return "one" }
      return "other"
    }
  }

  // MARK: - Helpers

  /// Splits a string on a separator, but only at the top level (not inside braces).
  private static func splitTopLevel(
    _ s: String,
    separator: Character,
    maxSplits: Int
  ) -> [String] {
    var parts: [String] = []
    var current = ""
    var depth = 0
    var splits = 0

    for ch in s {
      if ch == separator && depth == 0 && splits < maxSplits {
        parts.append(current)
        current = ""
        splits += 1
      } else {
        if ch == "{" { depth += 1 }
        if ch == "}" { depth -= 1 }
        current.append(ch)
      }
    }
    parts.append(current)
    return parts
  }

  /// Replaces `#` with the formatted number value.
  private static func replaceHash(_ s: String, with value: Double, locale: String) -> String {
    guard s.contains("#") else { return s }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: locale)
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = value == value.rounded() ? 0 : 3
    let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    return s.replacingOccurrences(of: "#", with: formatted)
  }

  private static func stringValue(_ value: Any) -> String {
    if let s = value as? String { return s }
    if let i = value as? Int { return String(i) }
    if let d = value as? Double {
      return d == d.rounded() ? String(Int(d)) : String(d)
    }
    return String(describing: value)
  }

  private static func numericValue(_ value: Any) -> Double {
    if let i = value as? Int { return Double(i) }
    if let d = value as? Double { return d }
    if let s = value as? String { return Double(s) ?? 0 }
    return 0
  }

  private enum FormatError: Error {
    case unmatchedBrace
    case missingArgument(String)
    case invalidFormat
    case noPluralMatch
    case noSelectMatch
  }
}
