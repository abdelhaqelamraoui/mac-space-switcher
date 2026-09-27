import Cocoa
import ApplicationServices
import CoreGraphics

/// Scrolling the mouse wheel over the top-right corner of the menu bar (the clock)
/// switches to the previous/next Space by posting Ctrl+Left / Ctrl+Right.
///
/// Requirements:
///  - App Sandbox must be OFF (event taps / event posting are blocked in the sandbox).
///  - Accessibility permission (System Settings > Privacy & Security > Accessibility).
///  - "Move left/right a space" enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
final class SpaceSwitcher {

    static let shared = SpaceSwitcher()

    var isEnabled = true

    // Hot zone: the right-most `zoneWidth` points of the menu bar on any display.
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

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

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
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled, isInHotZone(event.location) else {
            // Not over the menu-bar clock (or Space switching is disabled); let the
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

    /// `location` is in global display coordinates (origin top-left of the primary display).
    private func isInHotZone(_ point: CGPoint) -> Bool {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else {
            return false
        }
        let bounds = CGDisplayBounds(displayID)
        return point.y >= bounds.minY && point.y <= bounds.minY + zoneHeight
            && point.x >= bounds.maxX - zoneWidth && point.x <= bounds.maxX
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
