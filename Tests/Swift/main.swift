//
//  main.swift (settings rules tests)
//  Touch Up tests
//
//  Tests for the settings rules (GestureSettings.swift): the cases of T650Native's GestureConflictsTests that apply to
//  Touch Up (there is no three-finger drag here), the shared Mission Control / App Exposé finger count, and the
//  settings window's change sequence. Run with Tests/run-tests.sh.
//

import Foundation

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL Tests/Swift/main.swift:\(line): \(message())")
    }
}

func resolve(_ s: inout GestureSettings, _ changed: String) -> [String] { GestureConflicts.resolve(&s, changed: changed) }

// Resolve_Defaults_HaveNoClash
do {
    var s = GestureSettings.defaults
    for g in GestureConflicts.gestures {
        check(resolve(&s, g).isEmpty, "defaults clash on \(g)")
    }
    check(s == .defaults, "defaults changed")
}

// Resolve_PagesOnThreeFingers_MovesDesktopsToFourFingers_InsteadOfTurningItOff
do {
    var s = GestureSettings.defaults
    s.DesktopsFingers = .Three
    s.SwipeBetweenPages = true
    s.PagesTrigger = .ThreeFingerSwipe
    let off = resolve(&s, "PagesTrigger")
    check(off.isEmpty && s.SwipeBetweenDesktops && s.DesktopsFingers == .Four, "desktops should move to four fingers")
}

// Resolve_MovingDesktopsToThreeFingers_ForcesPagesToTwoFingers_WhenPagesUsesThree
do {
    var s = GestureSettings.defaults
    s.SwipeBetweenPages = true
    s.PagesTrigger = .ThreeFingerSwipe
    s.DesktopsFingers = .Three
    let off = resolve(&s, "DesktopsFingers")
    check(off.isEmpty && s.SwipeBetweenPages && s.PagesTrigger == .TwoFingerScroll, "pages should move to two-finger scroll, got \(s.PagesTrigger)")
}

// Resolve_TwoFingerScrollPages_DoesNotClashWithThreeFingerDesktops
do {
    var s = GestureSettings.defaults
    s.DesktopsFingers = .Three
    s.SwipeBetweenPages = true
    s.PagesTrigger = .TwoFingerScroll
    check(resolve(&s, "SwipeBetweenPages").isEmpty && s.DesktopsFingers == .Three, "no clash expected")
}

// Resolve_TwoOrThreeFingerPages_ClashesWithThreeFingerDesktops_SoDesktopsMovesToFour
do {
    var s = GestureSettings.defaults
    s.DesktopsFingers = .Three
    s.SwipeBetweenPages = true
    s.PagesTrigger = .TwoOrThreeFingerSwipe
    _ = resolve(&s, "PagesTrigger")
    check(s.DesktopsFingers == .Four && s.SwipeBetweenDesktops, "desktops should move to four")
}

// Resolve_ADisabledGesture_IsLeftAlone_EvenWhenItsTriggerWouldClash
do {
    var s = GestureSettings.defaults
    s.SwipeBetweenDesktops = false
    s.DesktopsFingers = .Three
    s.SwipeBetweenPages = true
    s.PagesTrigger = .ThreeFingerSwipe
    _ = resolve(&s, "SwipeBetweenPages")
    check(s.DesktopsFingers == .Three && !s.SwipeBetweenDesktops, "a disabled gesture is left alone")
}

// Resolve_MissionControlAndAppExposeOnThreeFingers_DoNotClash
do {
    var s = GestureSettings.defaults
    s.MissionControlFingers = .Three
    s.AppExposeFingers = .Three
    check(resolve(&s, "MissionControlFingers").isEmpty && s.MissionControl && s.AppExpose, "up and down do not clash")
}

// Resolve_DisablingAGesture_TurnsNothingOff / Resolve_NonGestureSetting_TurnsNothingOff
do {
    var s = GestureSettings.defaults
    s.SwipeBetweenDesktops = false
    check(resolve(&s, "SwipeBetweenDesktops").isEmpty, "disabling turns nothing off")
    check(resolve(&s, "Zoom").isEmpty && resolve(&s, "ScrollDirection").isEmpty, "non-gesture settings turn nothing off")
}

// Mission Control and App Exposé share a finger count; whichever changed wins.
do {
    let up = GestureSettings.defaults.applying([("MissionControlFingers", .string("Three"))]).settings
    check(up.MissionControlFingers == .Three && up.AppExposeFingers == .Three, "App Exposé follows Mission Control")
    let down = GestureSettings.defaults.applying([("AppExposeFingers", .string("Three"))]).settings
    check(down.MissionControlFingers == .Three && down.AppExposeFingers == .Three, "Mission Control follows App Exposé")
}

// The window's "choose a method, then turn on" sequence, as one change: turning pages on with three fingers while
// full-screen apps use three moves full-screen apps to four.
do {
    var start = GestureSettings.defaults
    start.DesktopsFingers = .Three
    start.SwipeBetweenPages = false
    let result = start.applying([("PagesTrigger", .string("ThreeFingerSwipe")), ("SwipeBetweenPages", .bool(true))])
    check(result.settings.SwipeBetweenPages && result.settings.PagesTrigger == .ThreeFingerSwipe, "pages on, three fingers")
    check(result.settings.DesktopsFingers == .Four && result.turnedOff.isEmpty, "desktops moved, not turned off")
}

// Values are checked: an unknown name, a wrong type and an unknown enum value change nothing.
do {
    var s = GestureSettings.defaults
    check(!s.set("Nope", to: .bool(true)), "unknown name")
    check(!s.set("Zoom", to: .double(1)), "wrong type")
    check(!s.set("PagesTrigger", to: .string("Sideways")), "unknown enum value")
    check(!s.set("ScrollSpeed", to: .double(50)), "the removed scroll speed is an unknown name")
}

// A saved file with missing or bad values keeps the defaults for those, and links the finger counts.
do {
    let json = #"{"Zoom": false, "PagesTrigger": "Sideways", "MissionControlFingers": "Three", "AppExposeFingers": "Four", "ScrollSpeed": 250}"#
    let s = try! JSONDecoder().decode(GestureSettings.self, from: Data(json.utf8))
    check(!s.Zoom && s.PagesTrigger == GestureSettings.defaults.PagesTrigger, "partial file")
    check(s.AppExposeFingers == .Three, "on load Mission Control's count wins")
    let reencoded = String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    check(!reencoded.contains("ScrollSpeed"), "an old file's ScrollSpeed is dropped")
    let roundTrip = try! JSONDecoder().decode(GestureSettings.self, from: try! JSONEncoder().encode(s))
    check(roundTrip == s, "round trip")
}


// An earlier build's separate keys are migrated: missing keys keep their defaults (the pages trigger included), and a
// clash between them is resolved.
do {
    check(GestureSettings.migratingLegacyKeys { _ in nil } == nil, "no old keys: nothing to migrate")

    let old: [String: Any] = [
        "gesture.zoom": false, "gesture.swipeBetweenPages": true, "gesture.pagesTrigger": 1,
        "gesture.fullScreenAppsFingers": 3, "gesture.missionControlFingers": 3, "gesture.lookUp": true,
    ]
    let s = GestureSettings.migratingLegacyKeys { old[$0] }!
    check(!s.Zoom && s.LookUp && s.SwipeBetweenPages && s.PagesTrigger == .ThreeFingerSwipe, "values carried over")
    check(s.MissionControlFingers == .Three && s.AppExposeFingers == .Three, "finger counts carried over and linked")
    check(s.DesktopsFingers == .Four, "pages and full-screen apps both on three fingers: full-screen apps moved to four")

    let noTrigger = GestureSettings.migratingLegacyKeys { ["gesture.zoom": true][$0] }!
    check(noTrigger.PagesTrigger == GestureSettings.defaults.PagesTrigger, "a missing pages trigger keeps the default")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
