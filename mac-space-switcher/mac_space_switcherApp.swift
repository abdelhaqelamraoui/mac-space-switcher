import SwiftUI
import ServiceManagement

@main
struct mac_space_switcherApp: App {

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("spaceSwitchingEnabled") private var spaceSwitchingEnabled = true
    @AppStorage("spaceSwitchingCorner") private var spaceSwitchingCorner = ScreenCorner.topRight
    @AppStorage("rightButtonScrollEnabled") private var rightButtonScrollEnabled = false
    @AppStorage("dockWindowSwitchingEnabled") private var dockWindowSwitchingEnabled = true

    init() {
        SpaceSwitcher.shared.isEnabled = spaceSwitchingEnabled
        SpaceSwitcher.shared.corner = spaceSwitchingCorner
        SpaceSwitcher.shared.rightButtonScrollEnabled = rightButtonScrollEnabled
        SpaceSwitcher.shared.start()
        DockWindowSwitcher.shared.isEnabled = dockWindowSwitchingEnabled
    }

    var body: some Scene {
        MenuBarExtra("Space Switcher", systemImage: "rectangle.3.group") {
            Text("Scroll over the \(spaceSwitchingCorner.title.lowercased()) corner to switch Spaces")
            Text("Scroll over a Dock icon to switch its windows")
            Divider()
            Toggle("Switch Spaces on Corner Scroll", isOn: Binding(
                get: { spaceSwitchingEnabled },
                set: {
                    spaceSwitchingEnabled = $0
                    SpaceSwitcher.shared.isEnabled = $0
                }
            ))
            Picker("Space Switching Corner", selection: Binding(
                get: { spaceSwitchingCorner },
                set: {
                    spaceSwitchingCorner = $0
                    SpaceSwitcher.shared.corner = $0
                }
            )) {
                ForEach(ScreenCorner.allCases) { corner in
                    Text(corner.title).tag(corner)
                }
            }
            Toggle("Switch Spaces on Right-Click + Scroll", isOn: Binding(
                get: { rightButtonScrollEnabled },
                set: {
                    rightButtonScrollEnabled = $0
                    SpaceSwitcher.shared.rightButtonScrollEnabled = $0
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
            Link("GitHub Repository", destination: URL(string: "https://github.com/abdelhaqelamraoui/mac-space-switcher")!)
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
