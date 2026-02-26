import SwiftUI
import AirStrings

struct LocaleSwitcherView: View {
    @Environment(\.airStrings) private var strings
    @State private var selectedLocale = "en"

    var body: some View {
        Section("Locale") {
            Picker("Locale", selection: $selectedLocale) {
                ForEach(DemoConfig.availableLocales, id: \.self) { locale in
                    Text(locale).tag(locale)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedLocale) { _, newLocale in
                Task {
                    await strings.setLocale(newLocale)
                }
            }
        }
    }
}
