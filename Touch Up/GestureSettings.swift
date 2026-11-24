//
//  GestureSettings.swift
//  Touch Up
//
//  The trackpad gesture settings, with the names, defaults and rules of the T650Native project's T650Settings and
//  GestureConflicts (src/T650Native/Settings/), so the settings window can be a port of its native one.
//

import Foundation

enum PagesTriggerChoice: String, Codable, CaseIterable { case TwoFingerScroll, TwoOrThreeFingerSwipe, ThreeFingerSwipe }

enum SwipeFingerCount: String, Codable, CaseIterable {
    case Three, Four
    var count: Int { self == .Three ? 3 : 4 }
}

/// One setting's value, as the catalog and the views handle them by name.
enum SettingValue: Equatable {
    case bool(Bool)
    case double(Double)
    case string(String)

    var bool: Bool? { if case .bool(let v) = self { return v } else { return nil } }
    var double: Double? {
        switch self {
        case .double(let v): return v
        default: return nil
        }
    }
    var string: String? { if case .string(let v) = self { return v } else { return nil } }
}

struct GestureSettings: Codable, Equatable {
    // Scrolling (always natural: the content follows the fingers)
    var ScrollMomentum = true

    // Pointing and clicking
    var SecondaryClick = true
    var LookUp = false

    // Scroll and zoom
    var Zoom = true
    var SmartZoom = true
    var Rotate = true

    // Gestures
    var NotificationCenter = true
    var SwipeBetweenPages = false
    var PagesTrigger: PagesTriggerChoice = .ThreeFingerSwipe
    var SwipeBetweenDesktops = true
    var DesktopsFingers: SwipeFingerCount = .Four
    var MissionControl = true
    var MissionControlFingers: SwipeFingerCount = .Four
    var AppExpose = true
    var AppExposeFingers: SwipeFingerCount = .Four
    var Launchpad = true
    var ShowDesktop = true

    static let defaults = GestureSettings()

    init() {}

    // Anything missing or unreadable keeps its default, so adding a setting later never breaks a saved file.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        read(.ScrollMomentum, &ScrollMomentum)
        read(.SecondaryClick, &SecondaryClick)
        read(.LookUp, &LookUp)
        read(.Zoom, &Zoom)
        read(.SmartZoom, &SmartZoom)
        read(.Rotate, &Rotate)
        read(.NotificationCenter, &NotificationCenter)
        read(.SwipeBetweenPages, &SwipeBetweenPages)
        read(.PagesTrigger, &PagesTrigger)
        read(.SwipeBetweenDesktops, &SwipeBetweenDesktops)
        read(.DesktopsFingers, &DesktopsFingers)
        read(.MissionControl, &MissionControl)
        read(.MissionControlFingers, &MissionControlFingers)
        read(.AppExpose, &AppExpose)
        read(.AppExposeFingers, &AppExposeFingers)
        read(.Launchpad, &Launchpad)
        read(.ShowDesktop, &ShowDesktop)
        linkExposeFingers()
    }

    // MARK: Access by name

    static let names: [String] = [
        "ScrollMomentum", "SecondaryClick", "LookUp", "Zoom", "SmartZoom", "Rotate",
        "NotificationCenter", "SwipeBetweenPages", "PagesTrigger", "SwipeBetweenDesktops", "DesktopsFingers",
        "MissionControl", "MissionControlFingers", "AppExpose", "AppExposeFingers", "Launchpad", "ShowDesktop",
    ]

    subscript(name: String) -> SettingValue? {
        switch name {
        case "ScrollMomentum": return .bool(ScrollMomentum)
        case "SecondaryClick": return .bool(SecondaryClick)
        case "LookUp": return .bool(LookUp)
        case "Zoom": return .bool(Zoom)
        case "SmartZoom": return .bool(SmartZoom)
        case "Rotate": return .bool(Rotate)
        case "NotificationCenter": return .bool(NotificationCenter)
        case "SwipeBetweenPages": return .bool(SwipeBetweenPages)
        case "PagesTrigger": return .string(PagesTrigger.rawValue)
        case "SwipeBetweenDesktops": return .bool(SwipeBetweenDesktops)
        case "DesktopsFingers": return .string(DesktopsFingers.rawValue)
        case "MissionControl": return .bool(MissionControl)
        case "MissionControlFingers": return .string(MissionControlFingers.rawValue)
        case "AppExpose": return .bool(AppExpose)
        case "AppExposeFingers": return .string(AppExposeFingers.rawValue)
        case "Launchpad": return .bool(Launchpad)
        case "ShowDesktop": return .bool(ShowDesktop)
        default: return nil
        }
    }

    /// Sets one setting by name. Refuses an unknown name, a value of the wrong type and an enum value that does not exist;
    /// nothing changes then.
    @discardableResult
    mutating func set(_ name: String, to value: SettingValue) -> Bool {
        switch (name, value) {
        case ("ScrollMomentum", .bool(let v)): ScrollMomentum = v
        case ("SecondaryClick", .bool(let v)): SecondaryClick = v
        case ("LookUp", .bool(let v)): LookUp = v
        case ("Zoom", .bool(let v)): Zoom = v
        case ("SmartZoom", .bool(let v)): SmartZoom = v
        case ("Rotate", .bool(let v)): Rotate = v
        case ("NotificationCenter", .bool(let v)): NotificationCenter = v
        case ("SwipeBetweenPages", .bool(let v)): SwipeBetweenPages = v
        case ("PagesTrigger", .string(let v)): guard let e = PagesTriggerChoice(rawValue: v) else { return false }; PagesTrigger = e
        case ("SwipeBetweenDesktops", .bool(let v)): SwipeBetweenDesktops = v
        case ("DesktopsFingers", .string(let v)): guard let e = SwipeFingerCount(rawValue: v) else { return false }; DesktopsFingers = e
        case ("MissionControl", .bool(let v)): MissionControl = v
        case ("MissionControlFingers", .string(let v)): guard let e = SwipeFingerCount(rawValue: v) else { return false }; MissionControlFingers = e
        case ("AppExpose", .bool(let v)): AppExpose = v
        case ("AppExposeFingers", .string(let v)): guard let e = SwipeFingerCount(rawValue: v) else { return false }; AppExposeFingers = e
        case ("Launchpad", .bool(let v)): Launchpad = v
        case ("ShowDesktop", .bool(let v)): ShowDesktop = v
        default: return false
        }
        return true
    }

    // MARK: Migration

    /// The settings an earlier build of this fork saved as separate "gesture.*" keys, read with `read` (UserDefaults'
    /// `object(forKey:)`); nil if it saved none. Missing keys keep their defaults, and clashes are resolved.
    static func migratingLegacyKeys(_ read: (String) -> Any?) -> GestureSettings? {
        guard read("gesture.zoom") != nil else { return nil }
        var s = GestureSettings()
        func bool(_ key: String, _ fallback: Bool) -> Bool { (read(key) as? Bool) ?? fallback }
        func int(_ key: String) -> Int? { read(key) as? Int }
        func fingers(_ key: String, _ fallback: SwipeFingerCount) -> SwipeFingerCount {
            switch int(key) { case 3: .Three; case 4: .Four; default: fallback }
        }
        s.ScrollMomentum = bool("gesture.scrollMomentum", s.ScrollMomentum)
        s.SecondaryClick = bool("gesture.secondaryClick", s.SecondaryClick)
        s.LookUp = bool("gesture.lookUp", s.LookUp)
        s.Zoom = bool("gesture.zoom", s.Zoom)
        s.SmartZoom = bool("gesture.smartZoom", s.SmartZoom)
        s.Rotate = bool("gesture.rotate", s.Rotate)
        s.SwipeBetweenPages = bool("gesture.swipeBetweenPages", s.SwipeBetweenPages)
        // The old build saved the framework's raw values: 0 two-finger scroll, 1 three-finger swipe, 2 two or three.
        if let trigger = int("gesture.pagesTrigger") {
            s.PagesTrigger = [0: .TwoFingerScroll, 1: .ThreeFingerSwipe, 2: .TwoOrThreeFingerSwipe][trigger] ?? s.PagesTrigger
        }
        s.SwipeBetweenDesktops = bool("gesture.swipeBetweenFullScreenApps", s.SwipeBetweenDesktops)
        s.DesktopsFingers = fingers("gesture.fullScreenAppsFingers", s.DesktopsFingers)
        s.MissionControl = bool("gesture.missionControl", s.MissionControl)
        s.AppExpose = bool("gesture.appExpose", s.AppExpose)
        s.MissionControlFingers = fingers("gesture.missionControlFingers", s.MissionControlFingers)
        s.Launchpad = bool("gesture.launchpad", s.Launchpad)
        s.ShowDesktop = bool("gesture.showDesktop", s.ShowDesktop)
        s.NotificationCenter = bool("gesture.notificationCenter", s.NotificationCenter)
        s.linkExposeFingers()
        // The old build had its own rule; settle any clash the way the window would (the gestures in catalog order).
        for gesture in GestureConflicts.gestures where s[gesture]?.bool == true {
            GestureConflicts.resolve(&s, changed: gesture)
        }
        return s
    }

    // MARK: Rules

    /// Mission Control (swipe up) and App Exposé (swipe down) share their finger count, as they do in macOS: the swipe that
    /// closes one is the swipe that opens the other. Whichever was changed wins; on load (nil) Mission Control does.
    mutating func linkExposeFingers(changed: String? = nil) {
        if changed == "AppExposeFingers" {
            MissionControlFingers = AppExposeFingers
        } else if changed == nil || changed == "MissionControlFingers" {
            AppExposeFingers = MissionControlFingers
        }
    }

    /// The settings after these changes, made in order, each followed by the rules (the shared finger count, then the
    /// trigger clashes), as T650Native's SettingsStore applies them. Also returns the gestures a clash turned off: with
    /// today's gestures there are none (each clashing one has a free trigger to move to), but a future gesture with a
    /// single trigger would be turned off, as in T650Native.
    func applying(_ changes: [(name: String, value: SettingValue)]) -> (settings: GestureSettings, turnedOff: [String]) {
        var next = self
        var off: [String] = []
        for change in changes {
            guard next.set(change.name, to: change.value) else { continue }
            next.linkExposeFingers(changed: change.name)
            for gesture in GestureConflicts.resolve(&next, changed: change.name) where !off.contains(gesture) {
                off.append(gesture)
            }
        }
        return (next, off.filter { next[$0]?.bool == false })
    }

}


/// Two gestures cannot share a trigger. A port of T650Native's GestureConflicts: the gesture just changed wins; another
/// enabled gesture that clashes with it is first moved to a trigger of its own, if it has a choice (swipe between pages,
/// swipe between full-screen apps), and only if it has none is it turned off.
///
/// A trigger is a finger count plus a motion ("3-h" is a three-finger horizontal swipe).
enum GestureConflicts {
    static let gestures = ["LookUp", "SwipeBetweenPages", "SwipeBetweenDesktops", "MissionControl", "AppExpose"]

    /// A trigger setting belongs to the gesture it configures.
    private static let ownerOfTrigger = [
        "PagesTrigger": "SwipeBetweenPages",
        "DesktopsFingers": "SwipeBetweenDesktops",
        "MissionControlFingers": "MissionControl",
        "AppExposeFingers": "AppExpose",
    ]

    /// Swipe between pages moves to the two-finger scroll first when it clashes.
    private static let pagesFallbacks: [PagesTriggerChoice] = [.TwoFingerScroll, .ThreeFingerSwipe, .TwoOrThreeFingerSwipe]

    /// Call after changing the setting called `changed`. Returns the gestures it turned off.
    @discardableResult
    static func resolve(_ s: inout GestureSettings, changed: String) -> [String] {
        let winner = ownerOfTrigger[changed] ?? changed
        guard gestures.contains(winner), s[winner]?.bool == true else { return [] }

        let claimed = claims(s, winner)
        var turnedOff: [String] = []
        for other in gestures where other != winner && s[other]?.bool == true {
            guard !claims(s, other).isDisjoint(with: claimed) else { continue }
            if retarget(&s, other, avoiding: claimed) { continue }
            s.set(other, to: .bool(false))
            turnedOff.append(other)
        }
        return turnedOff
    }

    private static func retarget(_ s: inout GestureSettings, _ gesture: String, avoiding claimed: Set<String>) -> Bool {
        switch gesture {
        case "SwipeBetweenDesktops":
            let original = s.DesktopsFingers
            for fingers in SwipeFingerCount.allCases where fingers != original {
                s.DesktopsFingers = fingers
                if claims(s, gesture).isDisjoint(with: claimed) { return true }
            }
            s.DesktopsFingers = original
            return false

        case "SwipeBetweenPages":
            let original = s.PagesTrigger
            for trigger in pagesFallbacks where trigger != original {
                s.PagesTrigger = trigger
                if claims(s, gesture).isDisjoint(with: claimed) { return true }
            }
            s.PagesTrigger = original
            return false

        default:
            return false
        }
    }

    static func claims(_ s: GestureSettings, _ gesture: String) -> Set<String> {
        switch gesture {
        case "LookUp": return ["3-tap"]
        case "SwipeBetweenPages":
            switch s.PagesTrigger {
            case .TwoFingerScroll: return ["2-h"]
            case .TwoOrThreeFingerSwipe: return ["2-h", "3-h"]
            case .ThreeFingerSwipe: return ["3-h"]
            }
        case "SwipeBetweenDesktops": return ["\(s.DesktopsFingers.count)-h"]
        case "MissionControl": return ["\(s.MissionControlFingers.count)-up"]
        case "AppExpose": return ["\(s.AppExposeFingers.count)-down"]
        default: return []
        }
    }
}
