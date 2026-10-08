<div align="center">

<img src="docs/logo.png" width="160" alt="Mac Space Switcher logo">

# Mac Space Switcher

**Switch macOS Spaces with your mouse wheel.**<br>
Scroll over the clock in the menu bar, any screen corner you pick, or hold right-click and scroll anywhere.

![Platform](https://img.shields.io/badge/platform-macOS%2026.1%2B-1d1d1f?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![Sandbox](https://img.shields.io/badge/private%20APIs-none-6b46e6)

[Install](#install) · [Setup](#setup-required-once) · [Configuration](#configuration) · [Troubleshooting](#troubleshooting)

</div>

---

Trackpad users can swipe between Spaces (desktops). With a regular mouse there is no easy equivalent.
**Mac Space Switcher** is a tiny menu bar app that turns the wheel into a Space switcher: put the pointer
over the clock in the top-right corner and scroll. Prefer another corner, or want it to work anywhere
on screen? Pick a different corner, or turn on right-click + scroll, from the menu bar menu.

## Features

| | |
|---|---|
| 🖱️ **Scroll to switch Spaces** | Wheel up → previous Space, wheel down → next Space, over the hot corner (the clock by default) |
| 🪟 **Scroll to switch windows** | Scroll over an app's Dock icon to cycle through its open windows |
| 📐 **Pick your corner** | Top-right (the clock) by default — choose any screen corner from the menu bar menu |
| 👉 **Right-click + scroll** | Optional: hold the right mouse button and scroll anywhere to switch Spaces |
| 🖥️ **Multi-display** | Works on the chosen corner of every connected display |
| 🫥 **Stays out of the way** | Menu bar icon only — no Dock icon, no window |
| 🚀 **Start at Login** | Optional toggle in the menu bar menu |
| 🔒 **No hacks** | No private APIs, no SIP changes — it uses the system's own shortcuts and Accessibility API |

## How it works

A global event tap watches scroll-wheel and right-mouse-button events.

- When the pointer is inside the hot zone (a 220 × 40 pt rectangle in the chosen screen corner —
  top-right, over the clock, by default), the scroll event is swallowed and the app posts the
  system's own **Ctrl + ← / Ctrl + →** shortcut, which macOS uses to move between Spaces. Toggle
  this off from the menu bar menu ("Switch Spaces on Corner Scroll") if you don't want it, or move
  it with "Space Switching Corner".
- With "Switch Spaces on Right-Click + Scroll" on, holding the right mouse button and scrolling
  anywhere on screen posts the same shortcut. To tell a gesture from a click, the app holds the
  right-button press back until you release: scroll and no context menu appears; don't scroll and
  the click is replayed, so the context menu opens on release instead of on press. Moving the
  pointer more than a few points without scrolling hands the press back, so right-drags still work.
- When the pointer is over an app icon in the Dock, the scroll event is swallowed and the app
  uses the Accessibility API to find that app's open windows and raise the next/previous one —
  no window is closed or reordered, it's just brought to the front. Toggle this off from the menu
  bar menu ("Switch Windows on Dock Scroll") if you don't want it.

All three toggles are independent. Corner scroll and Dock scroll default to on; right-click + scroll
defaults to off because it changes when context menus appear.

## Requirements

- macOS 26.1 or later (the project's deployment target; lower it in Xcode to support older versions — `MenuBarExtra` needs macOS 13+)
- Xcode to build from source
- **Mission Control keyboard shortcuts enabled** (see below)

## Install

> **No prebuilt download.** The app isn't notarized by Apple, so a downloaded `.app` would be blocked by
> Gatekeeper. You need to build and archive it yourself — it takes a couple of minutes.

1. Clone the repo and open `mac-space-switcher.xcodeproj` in Xcode.
2. Select the `mac-space-switcher` target → **Signing & Capabilities**, and choose your own Team
   (a free Apple ID "Personal Team" is enough). Change the Bundle Identifier if Xcode says it's taken.
   Make sure **App Sandbox** is *not* enabled.
3. **Product → Archive**, then in the Organizer choose **Distribute App → Custom → Copy App**
   and save the app.
4. Move the resulting `mac-space-switcher.app` to `/Applications` and launch it from there.

## Setup (required, once)

1. **Enable the shortcuts** — System Settings → Keyboard → Keyboard Shortcuts → **Mission Control**,
   and turn on **Move left a space** and **Move right a space** (Ctrl + ← / →).
2. **Grant Accessibility** — on first launch macOS asks for permission. Go to
   System Settings → Privacy & Security → **Accessibility** and switch **mac-space-switcher** on.
   If macOS also asks for **Input Monitoring**, allow it.
3. Quit the app from its menu bar icon and launch it again.

Now scroll over the clock.

## Configuration

Everything in the menu bar menu applies immediately and is remembered across launches:

| Menu item | Default | What it does |
| --- | --- | --- |
| Switch Spaces on Corner Scroll | On | Scroll over the hot corner to switch Spaces |
| Space Switching Corner | Top Right | Which screen corner is the hot corner: Top Left, Top Right, Bottom Left or Bottom Right |
| Switch Spaces on Right-Click + Scroll | Off | Hold the right mouse button and scroll anywhere to switch Spaces |
| Switch Windows on Dock Scroll | On | Scroll over a Dock icon to cycle that app's windows |
| Start at Login | Off | Launch the app when you log in |
| GitHub Repository | — | Opens this repo in your browser |

> With a bottom corner selected, the hot corner takes priority over any Dock icon inside it:
> scrolling there switches Spaces rather than that app's windows.

For finer tuning, tweak the constants at the top of `mac-space-switcher/SpaceSwitcher.swift` (Spaces) or
`mac-space-switcher/DockWindowSwitcher.swift` (Dock windows) — both share the same shape:

| Constant          | Default | Meaning                                          |
| ----------------- | ------- | ------------------------------------------------ |
| `zoneWidth`       | `220`   | Width (pt) of the hot zone from the left/right edge of the chosen corner (Spaces only) |
| `zoneHeight`      | `40`    | Height (pt) of the hot zone from the top/bottom edge of the chosen corner (Spaces only) |
| `scrollThreshold` | `3`     | Scroll amount needed for one switch              |
| `cooldown`        | `0.35`  | Minimum seconds between switches                 |
| `invertDirection` | `false` | Flip scroll direction                            |
| `dragSlop`        | `4`     | Pointer movement (pt) that turns a held right-click into a normal right-drag (Spaces only) |

## Troubleshooting

- **Nothing happens** — check `~/mac-space-switcher.log`. If it says *NOT trusted*, the Accessibility
  permission is missing or stale. Remove the app from the Accessibility list, run
  `tccutil reset Accessibility com.ostordev.mac-space-switcher`, launch again and re-grant.
- **Permission keeps disappearing after rebuilds** — unsigned/ad-hoc builds get a new identity each time.
  Sign with a real team in Xcode.
- **Spaces don't change but scrolling is captured** — the Mission Control shortcuts are disabled.
- **Context menus open when I release the right button, not when I press it** — that's the
  right-click + scroll option; turn it off in the menu bar menu if you don't use it.
- **Dock scroll doesn't work in a bottom corner** — the hot corner covers that Dock icon. Pick another
  corner or scroll over a different part of the Dock.
- **Won't work in the App Sandbox / Mac App Store** — global event taps are not allowed in the sandbox.

---

## License

No license chosen yet — add a `LICENSE` file (e.g. MIT) before publishing if you want others to reuse it.
