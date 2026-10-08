import Cocoa
import ApplicationServices
import CoreGraphics

/// Screen corner that acts as the scroll hot zone for switching Spaces.
enum ScreenCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
}

/// Scrolling the mouse wheel over a screen corner (by default the top-right one,
/// i.e. the menu bar clock) switches to the previous/next Space by posting Ctrl+Left / Ctrl+Right.
/// Optionally, holding the right mouse button and scrolling anywhere does the same.
///
/// Requirements:
///  - App Sandbox must be OFF (event taps / event posting are blocked in the sandbox).
///  - Accessibility permission (System Settings > Privacy & Security > Accessibility).
///  - "Move left/right a space" enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
final class SpaceSwitcher {

    static let shared = SpaceSwitcher()

    var isEnabled = true
    var corner: ScreenCorner = .topRight
    /// Hold the right mouse button and scroll anywhere to switch Spaces.
    var rightButtonScrollEnabled = false

    // Hot zone: a `zoneWidth` x `zoneHeight` rectangle in the chosen corner of any display.
    private let zoneWidth: CGFloat = 220
    private let zoneHeight: CGFloat = 40

    // Scroll tuning.
    private let scrollThreshold: Double = 3      // accumulated wheel points needed per switch
    private let cooldown: TimeInterval = 0.35    // minimum time between switches (animation)

    // If scrolling up/right feels backwards, flip this.
    private let invertDirection = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accumulated: Double = 0
    private var lastSwitch = Date.distantPast

    // Right-button gesture. The button press is held back until we know whether it is
    // a gesture (scrolled -> no context menu) or a plain click (replayed on release).
    private var rightHeld = false
    private var rightGestureUsed = false
    private var pendingRightDown: CGEvent?
    private let dragSlop: CGFloat = 4            // movement that turns the press into a real right-drag
    private static let replayTag: Int64 = 0x53505357 // marks events we re-post ourselves

    private init() {}

    /// Startup/permission log written to ~/mac-space-switcher.log (stdout isn't visible outside Xcode).
    static func log(_ message: String) {
        print(message)
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("mac-space-switcher.log")
        let line = "\(Date()) \(message)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard eventTap == nil else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Self.log("⚠️ NOT trusted for Accessibility. bundle=\(Bundle.main.bundlePath)")
            return
        }

        let types: [CGEventType] = [.scrollWheel, .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<SpaceSwitcher>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log("❌ Could not create event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.log("✅ running, trusted, tap created. bundle=\(Bundle.main.bundlePath)")
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps that are slow or on user input; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            // We may have missed the button release while the tap was off.
            rightHeld = false
            rightGestureUsed = false
            pendingRightDown = nil
            return Unmanaged.passUnretained(event)
        }
        if type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged {
            return handleRightButton(type: type, event: event)
        }
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        if rightHeld {
            // Scrolling with the right button held: this press is a gesture, not a click.
            rightGestureUsed = true
            pendingRightDown = nil
        } else if !(isEnabled && isInHotZone(event.location)) {
            // Not over the hot corner (or Space switching is disabled); let the
            // Dock switcher have a look.
            if DockWindowSwitcher.shared.handle(event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Trackpad/Magic Mouse gestures scroll in the menu bar normally; only hijack the wheel
        // and continuous scrolls alike, but swallow the event so nothing else reacts.
        let delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fallback = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let value = delta != 0 ? delta : fallback

        // Reset accumulation when direction changes.
        if value != 0, (value > 0) != (accumulated > 0), accumulated != 0 { accumulated = 0 }
        accumulated += value

        if abs(accumulated) >= scrollThreshold,
           Date().timeIntervalSince(lastSwitch) >= cooldown {
            // Wheel up (positive) -> previous space (left); wheel down -> next (right).
            let goLeft = (accumulated > 0) != invertDirection
            accumulated = 0
            lastSwitch = Date()
            DispatchQueue.main.async { Self.postSpaceShortcut(left: goLeft) }
        } else if Date().timeIntervalSince(lastSwitch) < cooldown {
            accumulated = 0
        }

        return nil // swallow
    }

    private func handleRightButton(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Our own replayed click: let it through untouched.
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown:
            guard rightButtonScrollEnabled else { break }
            rightHeld = true
            rightGestureUsed = false
            pendingRightDown = event.copy()
            accumulated = 0
            return nil

        case .rightMouseDragged:
            guard rightHeld else { break }
            if rightGestureUsed { return nil }
            if let down = pendingRightDown {
                let dx = event.location.x - down.location.x
                let dy = event.location.y - down.location.y
                if hypot(dx, dy) < dragSlop { return nil }
                // A real right-drag: hand the press back and stop tracking it.
                Self.replay(down)
            }
            rightHeld = false
            pendingRightDown = nil

        case .rightMouseUp:
            guard rightHeld else { break }
            let down = pendingRightDown
            rightHeld = false
            pendingRightDown = nil
            if rightGestureUsed { return nil }
            // Plain right-click: deliver the press we held back, then the release.
            if let down, let up = event.copy() {
                Self.replay(down)
                Self.replay(up)
                return nil
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private static func replay(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: replayTag)
        event.post(tap: .cgSessionEventTap)
    }

    /// `location` is in global display coordinates (origin top-left of the primary display).
    private func isInHotZone(_ point: CGPoint) -> Bool {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else {
            return false
        }
        let bounds = CGDisplayBounds(displayID)
        let inX = corner.isLeft
            ? point.x >= bounds.minX && point.x <= bounds.minX + zoneWidth
            : point.x >= bounds.maxX - zoneWidth && point.x <= bounds.maxX
        let inY = corner.isTop
            ? point.y >= bounds.minY && point.y <= bounds.minY + zoneHeight
            : point.y >= bounds.maxY - zoneHeight && point.y <= bounds.maxY
        return inX && inY
    }

    // MARK: - Space switching

    private static func postSpaceShortcut(left: Bool) {
        let keyCode: CGKeyCode = left ? 123 : 124 // ←  / →
        let source = CGEventSource(stateID: .hidSystemState)
        // Arrow keys carry these flags on real hardware; Mission Control's shortcut needs them.
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]

        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }
}
