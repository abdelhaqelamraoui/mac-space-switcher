import SwiftUI
import ServiceManagement

@main
struct mac_space_switcherApp: App {

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        SpaceSwitcher.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("Space Switcher", systemImage: "rectangle.3.group") {
            Text("Scroll over the clock to switch Spaces")
            Divider()
            Toggle("Start at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            SpaceSwitcher.log("⚠️ Start at Login failed: \(error.localizedDescription)")
        }
        // Reflect the real state (e.g. if the user must approve it in System Settings).
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
