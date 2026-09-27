import SwiftUI
import ServiceManagement

@main
struct mac_space_switcherApp: App {

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("spaceSwitchingEnabled") private var spaceSwitchingEnabled = true
    @AppStorage("dockWindowSwitchingEnabled") private var dockWindowSwitchingEnabled = true

    init() {
        SpaceSwitcher.shared.isEnabled = spaceSwitchingEnabled
        SpaceSwitcher.shared.start()
        DockWindowSwitcher.shared.isEnabled = dockWindowSwitchingEnabled
    }

    var body: some Scene {
        MenuBarExtra("Space Switcher", systemImage: "rectangle.3.group") {
            Text("Scroll over the clock to switch Spaces")
            Text("Scroll over a Dock icon to switch its windows")
            Divider()
            Toggle("Switch Spaces on Menu Bar Scroll", isOn: Binding(
                get: { spaceSwitchingEnabled },
                set: {
                    spaceSwitchingEnabled = $0
                    SpaceSwitcher.shared.isEnabled = $0
                }
            ))
            Toggle("Switch Windows on Dock Scroll", isOn: Binding(
                get: { dockWindowSwitchingEnabled },
                set: {
                    dockWindowSwitchingEnabled = $0
                    DockWindowSwitcher.shared.isEnabled = $0
                }
            ))
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
