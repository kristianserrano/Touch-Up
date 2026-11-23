//
//  SettingsCatalog.swift
//  Touch Up
//
//  What the settings window shows: the panes, every setting's name, explanation, note, icon and choices, and how its
//  animation looks. A port of the T650Native project's catalog (src/T650Native/Settings/SettingsCatalog.cs and
//  native/SettingsApp/Sources/T650Settings/SettingsCatalog.swift), with the same labels and texts where the gesture is the
//  same, and touchscreen wording where it differs. The pad-only settings (pointer speed, tap to click, corner clicks, the
//  three-finger drag) are replaced by Touch Up's own: a touchscreen clicks and drags right under the finger.
//

import Foundation

struct Option: Identifiable, Hashable {
    let value: String
    let label: String
    /// A shorter wording for a card's summary, where the label is too long.
    var short: String? = nil
    var id: String { value }
}

enum Control: Identifiable {
    /// A measurement with a unit (Touch Up's own: millimetres and seconds).
    case measure(name: String, label: String, range: ClosedRange<Double>, step: Double, format: String)
    /// An extra on/off inside a group (the group's own switch is `SettingGroup.toggle`).
    case toggle(name: String, label: String, text: String?)
    /// A choice of trigger, finger count or direction.
    case picker(name: String, label: String, options: [Option])

    var id: String { settingName }

    var settingName: String {
        switch self {
        case .measure(let name, _, _, _, _), .toggle(let name, _, _), .picker(let name, _, _): name
        }
    }
}

/// A gesture's animation as the catalog describes it; `resolve` makes the picture for the settings as they are.
struct GlyphSpec {
    var fingers: Int
    var motion: Glyph.Motion
    /// What the screen in the picture shows the gesture doing.
    var scene: Glyph.Scene = .desktop
    var corner: Glyph.Corner? = nil
    var alt: Int? = nil
    var altReverse = false
    /// The setting that decides the finger count (a SwipeFingerCount), the scroll direction, or which of `cases`.
    var fingersFrom: String? = nil
    var scrollBarFrom: String? = nil
    var by: String? = nil
    var cases: [String: GlyphSpec]? = nil

    func resolve(in settings: (String) -> SettingValue?) -> Glyph {
        if let by, let chosen = cases?[settings(by)?.string ?? ""] {
            return chosen.resolve(in: settings)
        }
        return Glyph(
            fingers: fingersFrom.map { settings($0)?.string == "Three" ? 3 : 4 } ?? fingers,
            motion: motion,
            scene: scene,
            corner: corner,
            alt: alt,
            altReverse: altReverse,
            scrollBar: scrollBarFrom.flatMap { Glyph.ScrollBar(rawValue: settings($0)?.string?.lowercased() ?? "") })
    }
}

struct SettingGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// The on/off setting the group is about; nil for a group that has no switch of its own.
    var toggle: String? = nil
    var toggleLabel: String? = nil
    let text: String
    var note: String? = nil
    /// What the first choice of a gesture with a method says.
    var offLabel = SettingsCatalog.offLabel
    var controls: [Control] = []
    var glyph: GlyphSpec? = nil
    /// The picture while the gesture is off; nil is the empty pad.
    var offGlyph: GlyphSpec? = nil

    var switchLabel: String { toggleLabel ?? title }

    /// Every setting the group shows.
    var settingNames: [String] { (toggle.map { [$0] } ?? []) + controls.map(\.settingName) }

    /// A gesture with a switch and one method shows them as one choice: Off, then the methods.
    var method: (name: String, options: [Option])? {
        guard toggle != nil, controls.count == 1, case .picker(let name, _, let options) = controls[0] else { return nil }
        return (name, options)
    }
}

struct SettingsPane: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    /// Empty for a pane drawn by its own view (Touchscreens).
    var groups: [SettingGroup] = []

    static func == (a: SettingsPane, b: SettingsPane) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SettingsCatalog {
    static let offLabel = "Off"
    static let onLabel = "On"
    private static let gestureLabel = "Gesture"

    static let touchscreensPaneID = "screens"

    static let panes: [SettingsPane] = [
        SettingsPane(id: "pointing", title: "Pointing and Clicking", symbol: "cursorarrow.click", groups: [
            SettingGroup(id: "click", title: "Click", symbol: "hand.tap",
                         text: "Tap with one finger to click right where you touch. Tap twice to double-click.",
                         note: "Two taps this close together count as a double-click.",
                         controls: [.measure(name: "DoubleClickDistance", label: "Double-click zone", range: 0...8, step: 1, format: "%.0f mm")],
                         glyph: GlyphSpec(fingers: 1, motion: .tap, scene: .click)),
            SettingGroup(id: "secondary", title: "Secondary click", symbol: "contextualmenu.and.cursorarrow", toggle: "SecondaryClick",
                         text: "Just like on the right click of a mouse, the secondary click lets you open the contextual menu and access shortcuts. Tap with two fingers.",
                         note: "With Smart zoom on, a two-finger tap waits a moment for a second tap before it right-clicks.",
                         glyph: GlyphSpec(fingers: 2, motion: .tap, scene: .contextMenu)),
            SettingGroup(id: "lookup", title: "Look up & data detectors", symbol: "character.book.closed", toggle: "LookUp",
                         text: "Three finger tap on the screen.",
                         note: "Sends the macOS shortcut Control-Command-D.",
                         glyph: GlyphSpec(fingers: 3, motion: .tap, scene: .lookUp)),
            SettingGroup(id: "drag", title: "Drag & drop", symbol: "hand.draw",
                         text: "Touch an item and move your finger to drag it to a new location. Rest your finger on it to press and hold, for menus that open on a long press.",
                         note: "Lifting before the finger has moved past the threshold is a click. Increase it if taps turn into small drags.",
                         controls: [
                            .measure(name: "DragThreshold", label: "Drag threshold", range: 1...8, step: 0.5, format: "%.1f mm"),
                            .measure(name: "LongPressDuration", label: "Press and hold delay", range: 0.2...1.5, step: 0.1, format: "%.1f s"),
                         ],
                         glyph: GlyphSpec(fingers: 1, motion: .hold, scene: .drag)),
        ]),
        SettingsPane(id: "two", title: "Scroll and Zoom", symbol: "scroll", groups: [
            SettingGroup(id: "scroll", title: "Two-finger scroll", symbol: "arrow.up.and.down",
                         text: "Use two fingers by sliding horizontally or vertically to scroll through content.",
                         note: "Natural: the content follows your fingers. A slow stroke keeps it right under them; a fast one sends it further, as on a trackpad.",
                         controls: [
                            .picker(name: "ScrollDirection", label: "Scroll direction", options: [
                                Option(value: "Standard", label: "Standard"),
                                Option(value: "Natural", label: "Natural"),
                            ]),
                            .toggle(name: "ScrollMomentum", label: "Momentum",
                                    text: "Keep scrolling for a moment after your fingers lift. Touching the screen stops it."),
                         ],
                         glyph: GlyphSpec(fingers: 2, motion: .vertical, scene: .scroll, alt: 2, altReverse: true, scrollBarFrom: "ScrollDirection")),
            SettingGroup(id: "zoom", title: "Zoom", symbol: "plus.magnifyingglass", toggle: "Zoom",
                         text: "Two-finger pinch in/out on the screen to enlarge or reduce your view.",
                         glyph: GlyphSpec(fingers: 2, motion: .zoom, scene: .zoom)),
            SettingGroup(id: "smartzoom", title: "Smart zoom", symbol: "arrow.up.left.and.down.right.magnifyingglass", toggle: "SmartZoom",
                         text: "Two-finger double tap on the screen to quickly zoom in and back out of a webpage or PDF.",
                         note: "With Smart zoom off, a two-finger tap right-clicks at once instead of waiting a moment for a second tap.",
                         glyph: GlyphSpec(fingers: 2, motion: .double, scene: .smartZoom)),
            SettingGroup(id: "rotate", title: "Rotate", symbol: "rotate.right", toggle: "Rotate",
                         text: "Move two fingers around each other to rotate a photo or other item.",
                         glyph: GlyphSpec(fingers: 2, motion: .rotate, scene: .rotate)),
        ]),
        SettingsPane(id: "multi", title: "Gestures", symbol: "hand.raised.fingers.spread", groups: [
            SettingGroup(id: "notification", title: "Notification Center", symbol: "bell.badge", toggle: "NotificationCenter",
                         text: "Two-finger swipe from the right edge to catch up on notifications you have missed or check your widgets.",
                         glyph: GlyphSpec(fingers: 2, motion: .edge, scene: .notificationCenter)),
            SettingGroup(id: "pages", title: "Swipe between pages", symbol: "arrow.left.arrow.right", toggle: "SwipeBetweenPages",
                         text: "Show the previous or next page in a file or your web history.",
                         controls: [.picker(name: "PagesTrigger", label: gestureLabel, options: [
                            Option(value: "TwoFingerScroll", label: "Two-finger scroll left or right"),
                            Option(value: "TwoOrThreeFingerSwipe", label: "Two or three-finger swipe left or right", short: "Two or three-finger swipe"),
                            Option(value: "ThreeFingerSwipe", label: "Three-finger swipe left or right"),
                         ])],
                         glyph: GlyphSpec(fingers: 3, motion: .horizontal, scene: .pages, by: "PagesTrigger", cases: [
                            "TwoFingerScroll": GlyphSpec(fingers: 2, motion: .horizontal, scene: .pages),
                            "TwoOrThreeFingerSwipe": GlyphSpec(fingers: 2, motion: .horizontal, scene: .pages, alt: 3),
                         ])),
            SettingGroup(id: "desktops", title: "Swipe between full-screen apps", symbol: "rectangle.split.3x1", toggle: "SwipeBetweenDesktops",
                         text: "Move between desktops and full-screen apps.",
                         controls: [fingers("DesktopsFingers", "swipe left or right")],
                         glyph: GlyphSpec(fingers: 0, motion: .horizontal, scene: .spaces, fingersFrom: "DesktopsFingers")),
            SettingGroup(id: "mission", title: "Mission Control", symbol: "rectangle.3.group", toggle: "MissionControl",
                         text: "Swipe up to get a bird's-eye view of all your open windows, desktop spaces and any apps in full screen.",
                         controls: [fingers("MissionControlFingers", "swipe up")],
                         glyph: GlyphSpec(fingers: 0, motion: .up, scene: .missionControl, fingersFrom: "MissionControlFingers")),
            SettingGroup(id: "expose", title: "App Exposé", symbol: "macwindow.on.rectangle", toggle: "AppExpose",
                         text: "Swipe down to see all windows of the app you're currently using.",
                         controls: [fingers("AppExposeFingers", "swipe down")],
                         glyph: GlyphSpec(fingers: 0, motion: .down, scene: .appExpose, fingersFrom: "AppExposeFingers")),
            SettingGroup(id: "launchpad", title: "Launchpad", symbol: "square.grid.3x3", toggle: "Launchpad",
                         text: "Four-finger pinch to quickly look for an app.",
                         glyph: GlyphSpec(fingers: 4, motion: .pinch, scene: .launchpad)),
            SettingGroup(id: "showdesktop", title: "Show desktop", symbol: "menubar.dock.rectangle", toggle: "ShowDesktop",
                         text: "Four-finger spread to show your desktop.",
                         glyph: GlyphSpec(fingers: 4, motion: .spread, scene: .showDesktop)),
        ]),
        SettingsPane(id: touchscreensPaneID, title: "Touchscreens", symbol: "hand.point.up.left"),
    ]

    private static func fingers(_ name: String, _ what: String) -> Control {
        .picker(name: name, label: gestureLabel, options: [
            Option(value: "Three", label: "Three-finger \(what)"),
            Option(value: "Four", label: "Four-finger \(what)"),
        ])
    }

    static var allGroups: [SettingGroup] { panes.flatMap(\.groups) }

    /// The groups that show any of these settings, in the window's order.
    static func groups(containing names: some Collection<String>) -> [SettingGroup] {
        allGroups.filter { group in names.contains { group.settingNames.contains($0) } }
    }

    /// A card's summary: a group with a switch says its choice (short wording, or Off, or On); one without says its controls
    /// ("Natural").
    static func summary(_ group: SettingGroup, in settings: (String) -> SettingValue?) -> String {
        if let toggle = group.toggle {
            guard settings(toggle)?.bool == true else { return group.offLabel }
            guard let method = group.method else { return onLabel }
            return method.options.shortLabel(for: settings(method.name)?.string) ?? ""
        }

        return group.controls.compactMap { control -> String? in
            switch control {
            case .measure(let name, let label, _, _, let format): "\(label): \(String(format: format, settings(name)?.double ?? 0))".lowercasedFirst
            case .picker(let name, _, let options): options.shortLabel(for: settings(name)?.string)?.lowercased()
            case .toggle: nil
            }
        }.joined(separator: ", ").capitalizedFirst
    }

    /// What a group is set to, in full (the confirmation's from and to).
    static func describe(_ group: SettingGroup, in settings: (String) -> SettingValue?) -> String {
        if let toggle = group.toggle {
            guard settings(toggle)?.bool == true else { return group.offLabel }
            guard let method = group.method else { return onLabel }
            let value = settings(method.name)?.string
            return method.options.label(for: value) ?? value ?? ""
        }

        return group.controls.map { control in
            switch control {
            case .measure(let name, let label, _, _, let format): "\(label) \(String(format: format, settings(name)?.double ?? 0))"
            case .toggle(let name, let label, _): "\(label) \((settings(name)?.bool == true ? onLabel : offLabel).lowercased())"
            case .picker(let name, let label, let options): "\(label) \(options.label(for: settings(name)?.string) ?? settings(name)?.string ?? "")"
            }
        }.joined(separator: ", ")
    }

    /// The group's picture as the settings say it is now. A gesture that is off shows its off picture, or the empty pad.
    static func glyph(for group: SettingGroup, in settings: (String) -> SettingValue?) -> Glyph? {
        if let toggle = group.toggle, settings(toggle)?.bool != true {
            return group.offGlyph?.resolve(in: settings) ?? Glyph.off
        }
        return group.glyph?.resolve(in: settings)
    }
}

extension [Option] {
    func label(for value: String?) -> String? { first { $0.value == value }?.label }
    func shortLabel(for value: String?) -> String? { first { $0.value == value }.map { $0.short ?? $0.label } }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
