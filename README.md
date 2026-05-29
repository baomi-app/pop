# Pop · the first kernel of baomi 🌽

A screenshot tool for macOS. **Snap, and it pops.**

[中文说明](README.zh-Hans.md)

## Download

Grab the latest `Pop.zip` from [Releases](../../releases), unzip it, and drag `Pop.app` into Applications.

The first launch is blocked by Gatekeeper ("Apple could not verify…"). Pick one fix:

**A. Terminal** (fastest)

```bash
xattr -dr com.apple.quarantine /Applications/Pop.app
```

**B. System Settings rescue**

1. Double-click `Pop.app`; after it's blocked, open **System Settings → Privacy & Security**
2. Scroll to the bottom, find "Pop was blocked" and click **Open Anyway**
3. Enter your password → click **Open** in the dialog

After the first time, double-clicking works normally.

## Usage

Press `⌘⇧X` to bring up the selection overlay:

- Hover → highlights the window under the cursor; **click** = capture window
- **Drag** = capture region
- **↩** = capture full screen · **⎋** = cancel

The result is copied to the clipboard automatically. Everything else (custom hotkey,
save-to-disk, launch at login) lives in the menu-bar icon → Preferences.

On the first capture, macOS asks for **Screen Recording** permission. Grant it, then
quit and relaunch Pop.

## Development

Requires macOS 14+ and Xcode 26+. The project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen); the `.xcodeproj` is not committed
(regenerate it after editing `project.yml`).

```bash
# Generate the Xcode project
xcodegen generate

# Develop in Xcode
open Pop.xcodeproj

# Or: build + run from the command line
scripts/make-app.sh Debug --run
```

## Tech stack

Swift + SwiftUI + AppKit + ScreenCaptureKit. Native, with no third-party dependencies.

## Layout

```
Sources/Pop/                  Source
  PopApp.swift                  Entry point (MenuBarExtra menu-bar app)
  Brand.swift                   Brand colors + microcopy
  MenuContent.swift             Menu content
  CaptureCoordinator.swift      Capture flow orchestration
  RegionSelectionController     Selection overlay (hover/click/drag)
  ScreenCaptureService          ScreenCaptureKit capture
  HotkeyConfig / HotkeyManager / CarbonHotkey   Global hotkey
  SettingsView.swift            Preferences
  ClipboardService / ImageSaver / HistoryStore / Toast
  Localizable.xcstrings         Localized strings (zh-Hans / en)
App/                          Info.plist + signing entitlements
project.yml                   XcodeGen spec (generates Pop.xcodeproj)
scripts/make-app.sh           Build script (xcodebuild)
design/                       Icon design files
```
