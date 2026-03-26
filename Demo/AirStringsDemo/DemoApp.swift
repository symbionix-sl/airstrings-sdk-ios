import SwiftUI
@testable import AirStrings

@main
struct DemoApp: App {
  @State private var airStrings = AirStrings(
    configuration: AirStringsConfiguration(
      projectId: DemoConfig.projectId,
      publicKeys: [DemoConfig.publicKeyBase64],
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
