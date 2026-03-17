import SwiftUI
import AirStrings

struct StringListView: View {
  @Environment(\.airStrings) private var strings

  private let demoKeys = [
    "greeting",
    "farewell",
    "app.title",
    "settings.theme",
    "settings.language",
    "onboarding.welcome",
  ]

  private let icuDemoKeys: [(key: String, args: [String: Any])] = [
    ("items.count", ["count": 1]),
    ("items.count", ["count": 5]),
    ("items.count", ["count": 0]),
  ]

  var body: some View {
    NavigationStack {
      List {
        Section("Strings") {
          ForEach(demoKeys, id: \.self) { key in
            stringRow(key: key, value: strings[key])
          }
        }

        Section("ICU Formatting") {
          ForEach(Array(icuDemoKeys.enumerated()), id: \.offset) { _, demo in
            let formatted = strings.string(demo.key, args: demo.args)
            let argsDescription = demo.args.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")

            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text("\(demo.key) (\(argsDescription))")
                  .font(.caption)
                  .fontDesign(.monospaced)
                  .foregroundStyle(.tertiary)
                Text(formatted)
                  .font(.body)
                  .foregroundStyle(formatted == demo.key ? .secondary : .primary)
                  .italic(formatted == demo.key)
              }
              Spacer()
            }
            .padding(.vertical, 2)
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Strings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          LocaleSwitcherView()
        }
      }
      .refreshable {
        await strings.refresh()
      }
    }
  }

  private func stringRow(key: String, value: String) -> some View {
    let isFallback = value == key

    return HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(key)
          .font(.caption)
          .fontDesign(.monospaced)
          .foregroundStyle(.tertiary)
        Text(value)
          .font(.body)
          .foregroundStyle(isFallback ? .secondary : .primary)
          .italic(isFallback)
      }
      Spacer()
      if isFallback {
        Image(systemName: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 2)
  }
}
