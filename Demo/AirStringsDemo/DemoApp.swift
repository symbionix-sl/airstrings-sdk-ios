import SwiftUI
import AirStrings

@main
struct DemoApp: App {
    @State private var airStrings = AirStrings(
        configuration: AirStringsConfiguration(
            projectId: DemoConfig.projectId,
            publicKeys: [DemoConfig.keyId: DemoConfig.publicKeyData],
            locale: .fixed("en"),
            baseURL: DemoConfig.baseURL
        )
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.airStrings, airStrings)
        }
    }
}
