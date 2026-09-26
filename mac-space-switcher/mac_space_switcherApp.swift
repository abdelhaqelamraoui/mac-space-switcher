import SwiftUI

@main
struct mac_space_switcherApp: App {

    init() {
        SpaceSwitcher.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("Space Switcher", systemImage: "rectangle.3.group") {
            Text("Scroll over the clock to switch Spaces")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
