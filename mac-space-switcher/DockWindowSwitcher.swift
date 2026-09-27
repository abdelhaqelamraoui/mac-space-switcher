import Cocoa
import ApplicationServices
import CoreGraphics

/// Scrolling the mouse wheel/trackpad over an app's icon in the Dock cycles through
/// that app's open windows (e.g. three Chrome windows -> scroll to switch between them).
///
/// Uses the same Accessibility permission already required by `SpaceSwitcher`; no
/// additional permission or private API is needed.
final class DockWindowSwitcher {

    static let shared = DockWindowSwitcher()

    var isEnabled = true

    // A trackpad/Magic Mouse scroll is a continuous device: one swipe sends a
    // "Began" event, several "Changed" events while your fingers move, and then
    // (after you lift them) a run of "momentum" events as it coasts to a stop. To
    // get exactly one switch per physical scroll — with the cursor never having to
    // leave the icon — momentum events are ignored outright, and a switch is only
    // ever armed once per gesture, starting fresh on each "Began". Plain wheel mice
    // report none of this phase info, so each of their events is just handled on
    // its own.
    private let scrollThreshold: Double = 0.5
    private let invertDirection = false

    private var accumulated: Double = 0
    private var gestureConsumed = false

    // Remembers which window index was last shown for each app, so repeated
    // scrolling steps forward/backward through the whole list.
    private var windowIndexByPID: [pid_t: Int] = [:]

    // Cached bounds of the Dock's actual icon strip(s), refreshed periodically since
    // the Dock can move, resize, or auto-hide. Padded slightly so hovering right at
    // the edge of an icon (or while it's magnifying) still counts.
    private var dockFrames: [CGRect] = []
    private var dockFramesUpdated = Date.distantPast
    private let dockFramesTTL: TimeInterval = 2
    private let dockFrameMargin: CGFloat = 24

    private init() {}

    /// Call from the shared scroll-wheel event tap. Returns true if the event was
    /// over the Dock and was handled (should be swallowed).
    func handle(_ event: CGEvent) -> Bool {
        guard isEnabled else { return false }
        let point = event.location
        guard isOverDock(point) else { return false }

        // Momentum events are the inertial tail after a trackpad swipe ends — never
        // let them trigger or re-arm a switch, however long they keep coming in.
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        guard momentumPhase == 0 else { return true }

        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let isContinuousDevice = scrollPhase != 0
            || event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        if isContinuousDevice {
            if scrollPhase == 1 { // Began: fingers just touched down for a new swipe.
                accumulated = 0
                gestureConsumed = false
            }
            guard !gestureConsumed else { return true }
        }

        let delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fallback = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let value = delta != 0 ? delta : fallback

        if value != 0, (value > 0) != (accumulated > 0), accumulated != 0 { accumulated = 0 }
        accumulated += value

        if abs(accumulated) >= scrollThreshold {
            // Wheel up (positive) -> previous window; wheel down -> next window.
            let forward = (accumulated < 0) != invertDirection
            accumulated = 0
            if isContinuousDevice { gestureConsumed = true }
            DispatchQueue.main.async { [weak self] in
                self?.switchWindow(at: point, forward: forward)
            }
        }

        return true
    }

    // MARK: - Dock geometry

    private func isOverDock(_ point: CGPoint) -> Bool {
        if Date().timeIntervalSince(dockFramesUpdated) > dockFramesTTL {
            refreshDockFrames()
        }
        if dockFrames.contains(where: { $0.contains(point) }) { return true }
        // Cache may be stale right after the Dock moved/resized/auto-hid; retry once.
        refreshDockFrames()
        return dockFrames.contains(where: { $0.contains(point) })
    }

    /// Reads the frame(s) of the Dock's own icon-list element(s) straight from the
    /// Accessibility tree. `CGWindowListCopyWindowInfo` is not reliable for this: on
    /// current macOS the Dock process owns a single on-screen window that covers the
    /// *entire* display (an invisible helper used for drag/hit-testing), so window
    /// bounds can't tell the visible icon strip apart from "the whole screen".
    private func refreshDockFrames() {
        dockFramesUpdated = Date()
        dockFrames = []

        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return }

        let appElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }

        let displays = activeDisplayBounds()
        for child in children {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            guard (roleValue as? String) == "AXList", let rect = frame(of: child) else { continue }
            // Safety net: whatever this element turns out to be, never treat something
            // covering most of a whole display as "the Dock" — that would swallow
            // scroll events everywhere on screen instead of just over the icons.
            let coversDisplay = displays.contains { display in
                rect.width >= display.width * 0.9 && rect.height >= display.height * 0.9
            }
            guard !coversDisplay else { continue }
            dockFrames.append(rect.insetBy(dx: -dockFrameMargin, dy: -dockFrameMargin))
        }
    }

    private func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.map { CGDisplayBounds($0) }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    // MARK: - Hit testing

    /// Walks up from the element under the cursor to find the enclosing Dock
    /// application icon (skips separators, folders, minimized-window tiles, etc.).
    private func dockAppItem(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementRef) == .success,
              var current = elementRef else { return nil }

        for _ in 0..<6 {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
            if (roleValue as? String) == "AXDockItem" {
                var subroleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subroleValue)
                return (subroleValue as? String) == "AXApplicationDockItem" ? current : nil
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = parentValue else { break }
            current = (parent as! AXUIElement)
        }
        return nil
    }

    private func runningApp(for dockItem: AXUIElement) -> NSRunningApplication? {
        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(dockItem, kAXURLAttribute as CFString, &urlValue) == .success,
           let url = urlValue as? URL,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == url }) {
            return app
        }
        var titleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(dockItem, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String {
            return NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title })
        }
        return nil
    }

    // MARK: - Window switching

    private func switchWindow(at point: CGPoint, forward: Bool) {
        guard let dockItem = dockAppItem(at: point),
              let app = runningApp(for: dockItem) else { return }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            // No AX windows to cycle (e.g. a single-window or menu-bar-only app) —
            // just bring it to the front.
            app.activate()
            return
        }

        let count = windows.count
        let current = windowIndexByPID[pid] ?? -1
        let next = forward ? (current + 1) % count : (current - 1 + count) % count
        windowIndexByPID[pid] = next
        let window = windows[next]

        var minimizedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
           (minimizedValue as? Bool) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
    }
}
