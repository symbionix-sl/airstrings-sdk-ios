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

    var body: some View {
        NavigationStack {
            List {
                LocaleSwitcherView()

                Section("Strings") {
                    ForEach(demoKeys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(strings[key])
                                .font(.body)
                                .foregroundStyle(
                                    strings[key] == key ? .secondary : .primary
                                )
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("AirStrings Demo")
            .refreshable {
                await strings.refresh()
            }
        }
    }
}
