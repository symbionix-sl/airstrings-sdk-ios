import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            StringListView()
                .tabItem {
                    Label("Strings", systemImage: "text.quote")
                }

            StatusView()
                .tabItem {
                    Label("Status", systemImage: "info.circle")
                }
        }
    }
}
