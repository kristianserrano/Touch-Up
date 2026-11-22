# Touch-Up
**Universal user-level driver to support touchscreens on macOS**
<hr/>

Most current touchscreens work with Microsoft Windows out-of-the-box as they implement a standardized communication via USB HID. However, nothing happens when connecting these screens to a Mac.
The goal of Touch Up was to provide a simple, general-purpose driver that enables plug-and-play support for touchscreens on macOS. 
The code in this repository provides a user-space driver that reads and processes the HID data into a set of touches and different utilities to inject mouse events into the system.

## What can you do with this App?
The Touch Up **utility app** allows you to control your Mac with any connected touch screen. One finger works directly on what it touches; two or more fingers use the same gestures as a Magic Trackpad, posted as native trackpad events:

- **One finger**: tap to click where you touch; move to drag (select text, move windows); rest the finger to press and hold
- **Two fingers**: scroll with momentum, pinch to zoom, rotate, tap for a secondary click, double-tap for smart zoom, scroll sideways to swipe between pages, swipe in from the right edge for Notification Center
- **Three fingers**: swipe between full-screen apps, swipe up for Mission Control and down for App Exposé, tap to Look Up (off by default)
- **Four fingers**: pinch for Launchpad, spread for Show Desktop

Every gesture, and the finger counts for swipes, can be changed in the app's settings, which follow the layout of System Settings › Trackpad.
The gesture recognition and the native event layout are ported from the T650Native touchpad driver; `Tests/run-tests.sh` runs the tests for the gesture logic.


### Installing the App
- Compile the app or [download the latest notarized build here](https://github.com/shueber/Touch-Up/releases).
- If you wish, move the app into your Applications folder and add it as a Login item.
- Launch it and allow Accessibility access.
- Plug in your touchscreen and start touching.


### Compatibility
Touch Up should work with any touchscreen that also works with Windows.
We used the following screens for testing:

- Iiyama TF3222MC and T2336MSC-B2
- 3M C4667PW




## The *TouchUpCore* Framework
Game developers, researchers, and others who need access to all touch data can also benefit from this project by integrating the TouchUpCore **framework** themselves. It provides simple access to all touches recognized on the touch surface, simplifying multitouch prototype development in macOS.

The Touch Up app itself is an example of integrating the TouchUpCore framework. You can have a look at the *DebugView* to see how you can visualize the different touch points. Remember that your app needs an Entitlement to access USB if running in the Sandbox.
