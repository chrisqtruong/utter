import SwiftUI

/// Settings → Keyboard: how to add the Utter keyboard, and which app to jump back to.
struct KeyboardSettingsView: View {
    @Environment(\.theme) private var theme
    @AppStorage(ReturnApp.storageKey) private var returnID = ""
    @State private var apps: [ReturnApp] = []

    var body: some View {
        Page(title: "keyboard", showsDone: false) {
            PageSection(label: "go back to",
                        note: "After the keyboard opens Utter, it starts listening and jumps to this app. It goes there even if you started somewhere else, so pick the one you use most.") {
                choice(id: "", name: "stay in utter")
                ForEach(apps) { app in choice(id: app.id, name: app.name.lowercased()) }
            }
            PageSection(label: "set it up") {
                step("1", "iPhone Settings → General → Keyboard → Keyboards → Add New Keyboard → Utter")
                step("2", "Tap Utter, then turn on Allow Full Access")
                step("3", "In any app, hold the globe key and pick Utter")
            }
        }
        .onAppear { apps = ReturnApp.installed }
    }

    private func choice(id: String, name: String) -> some View {
        let on = returnID == id
        return Button {
            returnID = id
            Haptics.tap()
        } label: {
            Text(name)
                .font(.mono(15, on ? .semibold : .regular))
                .foregroundStyle(on ? theme.text : theme.sub)
                .markerLoop(on, seed: name, color: theme.main, pad: 5)
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(n).font(.mono(14, .semibold)).foregroundStyle(theme.main).frame(width: 12)
            Text(text).font(.ui(16)).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
