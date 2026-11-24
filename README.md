# Magic Touch Up

**Magic Trackpad gestures for any touchscreen on macOS**

Most touchscreens work with Windows out of the box because they report touches in a standard way over USB HID. Connected
to a Mac, they usually do little or nothing. Magic Touch Up is a menu bar app that reads those reports, recognises
gestures in them, and posts them as mouse and native trackpad events. It runs in user space: there is no kernel
extension to install.

> Magic Touch Up is a fork of [Touch Up](https://github.com/shueber/Touch-Up) by Sebastian Hueber, rewritten around
> Magic Trackpad style gestures, with a new settings window and fixes for touchscreens that report oddly. It is not
> affiliated with the original project or with Apple. The touch-reading core and the TouchUpCore framework come from
> Touch Up; thanks to Sebastian for making it open source.

## Gestures

One finger works as on a tablet. Two or more work as on a Magic Trackpad.

| Fingers | Gesture | What it does | Default |
| --- | --- | --- | --- |
| 1 | Tap | Click where you touch; tap twice to double-click | Always on |
| 1 | Slide | Scroll | Always on |
| 1 | Touch and hold | Press the (left) mouse button; move to drag items, select text or move windows | Always on |
| 1 | Double-tap and drag | Drag without waiting; in text, selects word by word | Always on |
| 2 | Slide | Scroll | Always on |
| 2 | Tap | Secondary click | On |
| 2 | Double-tap | Smart zoom | On |
| 2 | Pinch | Zoom | On |
| 2 | Turn | Rotate | On |
| 2 | Swipe in from the right edge | Notification Center | On |
| 3 | Tap | Look up & data detectors (sends Control-Command-D) | Off |
| 2 or 3 | Swipe left or right | Swipe between pages | Off |
| 3 or 4 | Swipe left or right | Swipe between full-screen apps | On, 4 fingers |
| 3 or 4 | Swipe up | Mission Control | On, 4 fingers |
| 3 or 4 | Swipe down | App Exposé | On, 4 fingers |
| 4 | Pinch | Launchpad | On |
| 4 | Spread | Show desktop | On |

Scrolling always follows your fingers, and by default coasts for a moment after they lift. Touch the screen to stop it.

## Install

There are no prebuilt downloads of this fork yet, so you build it yourself. The original project's
[releases](https://github.com/shueber/Touch-Up/releases) do not include this fork's changes.

You need macOS 14 or later and Xcode (last built with Xcode 26.3).

1. Clone the repository:

   ```sh
   git clone https://github.com/kristianserrano/Touch-Up.git
   cd Touch-Up
   ```

2. Create `Config/Local.xcconfig` with your signing team, which git ignores. Your team ID is in
   Xcode › Settings › Accounts:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```

   Without a team, choose **Sign to Run Locally** in the targets' Signing & Capabilities tab.

3. Open `Touch Up.xcodeproj` and run the **Touch Up** scheme. The app it builds is called **Magic Touch Up**. It has no
   Dock icon; look for it in the menu bar.
4. Allow Accessibility access when asked, and Input Monitoring if macOS asks for it. Without Accessibility access,
   macOS silently drops every click and gesture.
5. Plug in your touchscreen and start touching.

To keep the app, move it to your Applications folder. To start it when you log in, add it in
System Settings › General › Login Items.

## Settings

Choose **Settings…** from the menu bar icon. Changes are saved as you make them.

| Pane | What you can change |
| --- | --- |
| **Pointing and Clicking** | Double-click zone, secondary click, look up, press and hold delay |
| **Scroll and Zoom** | Scroll threshold, momentum, zoom, smart zoom, rotate |
| **Gestures** | Notification Center, swipes, Mission Control, App Exposé, Launchpad, show desktop |
| **Touchscreens** | Which display each touchscreen is on, its real size, touch rotation, and advanced options |

- Two gestures cannot share a trigger. If a change would make them clash, the window shows what else would change and
  asks first.
- Mission Control and App Exposé always use the same number of fingers.
- **Reset to Defaults…** resets the gesture, click and drag settings and keeps your touchscreen settings.
- To pause the app, turn off **Control Mouse with Touch** in its menu. Touch is on again the next time the app starts.

## Troubleshooting

Start in **Settings › Touchscreens**. **Test…** shows the touches as the app reads them.

| Problem | Try |
| --- | --- |
| Touches show in the test but do nothing | Check that Accessibility access is granted and **Control mouse with touch** is on |
| Touches land on the wrong display | Select the display you touched, then choose your touchscreen in the **Touchscreen** menu |
| Touches land in the wrong place on the right display | Change **Touch rotation** |
| Gestures need too much or too little movement | Choose the real **Screen Size**; some displays report a wrong one |
| Taps turn into small scrolls | Increase **Scroll threshold** in Scroll and Zoom |
| A secondary click feels slow | Turn off **Smart zoom**, so a two-finger tap need not wait for a second tap |
| Touches flicker or drop out | Increase **Error resistance** in Advanced… |
| Stray touches in the top-left corner | Turn on **Ignore origin touches** in Advanced… (on by default) |
| Stray clicks from macOS also treating the screen as a mouse | Turn on **Exclusive access** in Advanced… |
| Touches near the edges land on the edge itself | Increase **Edge dead zone** in Advanced… |

## Compatibility

Magic Touch Up should work with any touchscreen that also works with Windows. These have been tested:

- JRP7813S 7″ 1024 × 600 (USB2IIC_CTP_CONTROL), with this fork. Set its Screen Size to 7″: it reports 31″.
- Iiyama TF3222MC and T2336MSC-B2, and 3M C4667PW, with the original Touch Up

The native gestures rely on event fields Apple does not document, so a macOS update can break them.

## The TouchUpCore framework

Apps that need the raw touches (games, research, multitouch prototypes) can use the TouchUpCore framework directly.
See [Using TouchUpCore](docs/DEVELOPMENT.md#using-touchupcore).

## Development

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers how the code is organised, how to run the tests, and how to record
touches from a screen that misbehaves.

## Credits and license

Touch Up was created by [Sebastian Hueber](https://github.com/shueber/Touch-Up). The gesture recognition, the native
event layout and the settings window are ported from the T650Native touchpad driver.

Released under the [MIT License](LICENSE).
