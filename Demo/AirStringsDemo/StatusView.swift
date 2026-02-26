import SwiftUI
import AirStrings

struct StatusView: View {
    @Environment(\.airStrings) private var strings

    var body: some View {
        NavigationStack {
            List {
                Section("SDK State") {
                    row("Ready", value: strings.isReady ? "Yes" : "No")
                    row("Locale", value: strings.currentLocale)
                    row("Revision", value: "\(strings.revision)")
                }

                Section("Configuration") {
                    row("Project ID", value: DemoConfig.projectId)
                    row("Base URL", value: DemoConfig.baseURL.absoluteString)
                    row("Key ID", value: DemoConfig.keyId)
                }

                Section {
                    Button("Refresh") {
                        Task { await strings.refresh() }
                    }
                }
            }
            .navigationTitle("Status")
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
