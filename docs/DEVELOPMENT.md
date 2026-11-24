# Development

For installing and using the app, see the [README](../README.md).

## Build

Set up signing as in the [README](../README.md#install), then run the **Touch Up** scheme in Xcode. To check that
everything compiles without signing:

```sh
xcodebuild -project "Touch Up.xcodeproj" -scheme "Touch Up" -configuration Debug \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Leave `DEVELOPMENT_TEAM` out of the project file: it would override `Config/Local.xcconfig` and show up in diffs.

The app is called Magic Touch Up, but some names are kept from Touch Up: the Xcode project, target and scheme, the
Swift module (`Touch_Up`, which the menu nib refers to) and the TouchUpCore framework.

## Test

```sh
Tests/run-tests.sh
```

There is no XCTest target. The script compiles the code that posts no events with `clang` and `swiftc`, and runs:

| Test | Covers |
| --- | --- |
| `Tests/GestureTests.m` | Recognition, swipe translation, the Dock swipe block, click counting, scroll speed and momentum, gesture defaults, and replays of recorded strokes |
| `Tests/Swift/main.swift` | The settings rules: trigger clashes, the shared finger count, value checks, reading and migrating saved settings |

`REPLAY_VERBOSE=1 Tests/run-tests.sh` also prints how each recorded multi-finger stroke was recognised.

The tests do not cover HID decoding, event posting or the user interface. Check changes to those on a touchscreen.

## How it fits together

```
touchscreen
   │  USB HID reports
   ▼
HIDInterpreter              decodes reports into contacts
   ▼
TUCTouchInputManager        keeps the touch set; maps touches to a screen, in mm and points
   │  one frame per report
   ▼
TUCGestureRecognizer        one per touchscreen; decides what the fingers mean
   │  TUCGestureEvent
   ▼
TUCGestureOutput            one, shared; posts mouse, scroll and native gesture events
```

### TouchUpCore (the framework: C and Objective-C)

| Files | Role |
| --- | --- |
| `HIDInterpreter` | Finds touchscreens and decodes their reports |
| `TUCTouchInputManager` | The entry point: touches, coordinates, settings, lift detection |
| `TUCTouchDelegate` | What the host app provides (which screen, its rotation and size) and is told |
| `TUCTouch`, `TUCScreen` | One finger; one connected display panel |
| `TUCGestureSettings` | Which gestures are on, and their finger counts |
| `TUCGestureRecognizer` | Frames to gestures. Makes no OS calls, so it is tested; its thresholds are properties |
| `TUCNativeGesture` | The pure half of the output: event fields, swipe translation, click counting, momentum |
| `TUCGestureOutput` | Posts the events. Main thread only |

### Touch Up (the app: Swift)

| File | Role |
| --- | --- |
| `AppDelegate` | The menu bar item and the windows |
| `TouchUp` | The model: settings, touchscreens, and the framework's delegate |
| `GestureSettings` | The gesture settings, their defaults, clash rules and migration |
| `SettingsCatalog` | Every pane, card, label and choice in the settings window |
| `SettingsEngine` | Reads and changes settings by name, with confirmation and reset |
| `SettingsView`, `TouchscreensPane` | The settings window |
| `GestureGlyph` | The animated gesture pictures |
| `DebugView`, `DebugOverlay` | The touch test (Test… in the Touchscreens pane) |

## Behaviour to preserve

- **Thresholds are in millimetres on the glass.** They are only right if the screen size is. A size set by the user wins
  over the one the display reports.
- **A settled finger count picks the gesture**, so fingers landing a moment apart do not change it.
- **Silence means the fingers lifted.** Some screens never report it: after 70 ms without reports a scroll coasts, and
  after 350 ms all that screen's fingers count as lifted.
- **Travel spent deciding on a scroll is dropped**, so it does not start with a jump.
- **Scrolling is always natural.** On a screen, anything else pulls the content away from the fingers.
- **Native event fields are undocumented.** `TUCNativeGesture.h` lists them, recorded from a real device. From macOS 27 a
  Dock swipe also needs an embedded HID block (`TUCDockSwipeBlock`). Look here first if swipes break after an update.

## Adding a gesture setting

1. `GestureSettings.swift`: add the property, then its line in `init(from:)`, `names`, the subscript and `set`.
2. `TUCGestureSettings`: add the property, copy it in `copyWithZone:` and set it in `defaultSettings`. The framework's
   and the app's defaults must match.
3. `TouchUp.swift`: pass it on in `GestureSettings.core`.
4. `SettingsCatalog.swift`: add the card.
5. If it can clash with another gesture, add its triggers to `GestureConflicts`.
6. Add tests.

## Recording touches

To find out why a screen misbehaves, add the environment variable `TOUCHUP_RECORD=1` to the Touch Up scheme
(Edit Scheme… › Run › Arguments) and run it. The Xcode console then shows:

| Line | Meaning |
| --- | --- |
| `F time count id:x,y …` | A frame: the fingers down, in mm. `F time 0` means all have lifted |
| `E kind=… fingers=… phase=… axis=… value=…` | A recognised event; the numbers are the enums in `TUCGestureRecognizer.h` and `TUCNativeGesture.h` |
| `O time …` | What the output did with scrolling |

Save the output under `Tests/Fixtures` and replay it in a test, as `testRecordedTwoFingerTaps` does; only the `F` lines
are read. Set the right Screen Size before recording, as the positions depend on it.

## Using TouchUpCore

Set `postMouseEvents` to false to read touches without controlling the Mac. Positions run from 0 to 1 across the
screen, from its top-left corner.

```swift
import TouchUpCore

final class TouchReader: NSObject, TUCTouchDelegate {
    let manager = TUCTouchInputManager()

    func start() {
        manager.delegate = self
        manager.postMouseEvents = false
        manager.start()
    }

    func touchesDidChange() {
        for case let touch as TUCTouch in manager.touchSet where touch.isActive() {
            print(touch.contactID, touch.location)
        }
    }

    func touchscreenDidConnect(withLocationID locationID: UInt32) {}
    func touchscreenDidDisconnect(withLocationID locationID: UInt32) {}

    // Which display the touchscreen is on.
    func touchscreen(forLocationID locationID: UInt32) -> TUCScreen? {
        TUCScreen.allScreens().first
    }

    // Extra rotation of the touch positions: 0, 90, 180 or 270.
    func digitizerRotation(forLocationID locationID: UInt32) -> CGFloat { 0 }
}
```

`touchSet` also holds touches that ended less than half a second ago, so check `isActive()`. Implement
`physicalSize(forLocationID:)` if the display reports a wrong size. A sandboxed app needs the
`com.apple.security.device.usb` entitlement. `DebugView.swift` shows how to draw the touches.
