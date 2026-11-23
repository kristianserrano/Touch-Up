//
//  Model.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 03.02.23.
//

import AppKit
import Combine
import TouchUpCore

class TouchUp: NSObject, ObservableObject {
    
    let touchManager: TUCTouchInputManager
    @Published var touches = [TUCTouch]()
    
    
    var observers = [AnyCancellable]()
    
    @Published var isPublishingMouseEventsEnabled = true
    
    @Published var connectionState: ConnectionState = .disconnected
    
    @Published var longPressDuration: TimeInterval = 0.5 // one finger resting this long presses the button
    @Published var dragThreshold: CGFloat = 3 // mm one finger travels before it presses the button and drags
    @Published var doubleClickDistance: CGFloat = 3 //mm
    @Published var edgeDeadZone: CGFloat = 0 // border along the screen edges [pt] in which the cursor is never posted
    @Published var errorResistance: NSInteger = 0 // num of Reports to wait before cancelling a touch
    @Published var ignoreOriginTouches: Bool = false
    @Published var isExclusiveAccessEnabled: Bool = false

    /// The trackpad gestures (named and ruled as in T650Native). Every change goes to the touch manager and is saved at once.
    @Published private(set) var gestures = GestureSettings() {
        didSet {
            touchManager.gestureSettings = gestures.core
            if let data = try? JSONEncoder().encode(gestures) {
                UserDefaults.standard.set(data, forKey: Self.gestureSettingsKey)
            }
        }
    }
    static let gestureSettingsKey = "gestureSettings"

    /// A change that moves other settings too, waiting for the user to confirm it (see `SettingsConfirmation`).
    @Published var confirmation: SettingsConfirmation?
    /// A short note at the bottom of the settings window (a reset done), cleared after a few seconds.
    @Published var settingsNote: String?

    @Published var areAdditionalDigitizerRotationSettingsVisible = false


    @Published var connectedScreens = [TUCScreen]()
    @Published var connectedDigitizers = [Digitizer]()

    /// Live config for every currently connected digitizer, keyed by `HIDLocationID`.
    /// Source of truth for the UI and for the delegate resolution.
    @Published var digitizerConfigs: [HIDLocationID: DigitizerConfig] = [:]

    /// All configs ever persisted (also for digitizers that are currently disconnected),
    /// keyed by `HIDLocationID`. Loaded once at launch, re-saved on every `persistMapping`.
    private var persistedConfigs: [HIDLocationID: DigitizerConfig] = [:]

    /// `CGDirectDisplayID` of the screen that connected most recently. Used as the implicit
    /// fallback target when a digitizer has no (matching) stored screen identity.
    var idOfLastAddedScreen: UInt?


    @Published var isAccessibilityAccessGranted = false



    @objc func screenParametersDidChange() {
        // identify which screen is newly added.
        let oldScreenList = self.connectedScreens
        self.connectedScreens = TUCScreen.allScreens()

        // a new screen appeared — remember it as the implicit fallback target.
        if connectedScreens.count > oldScreenList.count {
            let new = connectedScreens.first { s in
                !(oldScreenList.contains(where: {$0.id == s.id}))
            }
            if let new {
                self.idOfLastAddedScreen = new.id
            }
        }

        // The screen list was rebuilt, so any resolved mapping may have shifted.
        updateConnectionState()
    }

    
    func checkAccessibilityAccessGranted() {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        self.isAccessibilityAccessGranted = AXIsProcessTrustedWithOptions([checkOptPrompt: true] as CFDictionary?)
    }
    
    func grantAccessibilityAccess() {
        self.touchManager.triggerSystemAccessibilityAccessAlert()
        (NSApp.delegate as? AppDelegate)?.settingsWindow.close()
        self.isAccessibilityAccessGranted = true
    }
    
    
    override init() {
        self.touchManager = TUCTouchInputManager()

        super.init()

        self.loadDigitizerConfigs()
        self.screenParametersDidChange()
        
        self.touchManager.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(TouchUp.screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        initPreferences()
        
        checkAccessibilityAccessGranted()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
}


// MARK: - Loading, Saving and Syncing Settings with Framework
extension TouchUp {
    
    func initPreferences() {
        let defaults = UserDefaults.standard
        
        defaults.register(defaults: [
            "longPressDuration" : 0.5,
            "dragThreshold" : 3,
            "doubleClickDistance" : 8,
            "edgeDeadZone" : 0,
            "errorResistance" : 4,
            "ignoreOriginTouches" : true,
            "isExclusiveAccessEnabled" : false,
            "areAdditionalDigitizerRotationSettingsVisible" : false,
        ])
        
        longPressDuration = defaults.double(forKey: "longPressDuration")
        dragThreshold = defaults.double(forKey: "dragThreshold")
        doubleClickDistance = defaults.double(forKey: "doubleClickDistance")
        edgeDeadZone = defaults.double(forKey: "edgeDeadZone")
        errorResistance = defaults.integer(forKey: "errorResistance")
        ignoreOriginTouches = defaults.bool(forKey: "ignoreOriginTouches")
        isExclusiveAccessEnabled = defaults.bool(forKey: "isExclusiveAccessEnabled")


        self.observers = [
            $isPublishingMouseEventsEnabled.assign(to: \.postMouseEvents, on: touchManager),
            $longPressDuration.assign(to: \.longPressDuration, on: touchManager),
            $dragThreshold.assign(to: \.dragThreshold, on: touchManager),
            $doubleClickDistance.assign(to: \.doubleClickTolerance, on: touchManager),
            $edgeDeadZone.assign(to: \.edgeDeadZone, on: touchManager),
            $errorResistance.assign(to: \.errorResistance, on: touchManager),
            $ignoreOriginTouches.assign(to: \.ignoreOriginTouches, on: touchManager),
            
            $isExclusiveAccessEnabled.sink { [weak touchManager] seized in
                touchManager?.setTouchscreensSeized(seized)
            }
        ]
        
        
        
        gestures = Self.loadGestureSettings(from: defaults)

        areAdditionalDigitizerRotationSettingsVisible = defaults.bool(forKey: "areAdditionalDigitizerRotationSettingsVisible")
    }
    
    
    func savePreferences() {
        let defaults = UserDefaults.standard
        
        defaults.set(longPressDuration, forKey: "longPressDuration")
        defaults.set(dragThreshold, forKey: "dragThreshold")
        defaults.set(doubleClickDistance, forKey: "doubleClickDistance")
        defaults.set(edgeDeadZone, forKey: "edgeDeadZone")
        defaults.set(errorResistance, forKey: "errorResistance")
        defaults.set(ignoreOriginTouches, forKey: "ignoreOriginTouches")
        defaults.set(isExclusiveAccessEnabled, forKey: "isExclusiveAccessEnabled")

        defaults.set(areAdditionalDigitizerRotationSettingsVisible, forKey: "areAdditionalDigitizerRotationSettingsVisible")
    }

}


// MARK: - Trackpad Gestures
extension GestureSettings {
    /// The settings as the framework takes them.
    var core: TUCGestureSettings {
        let s = TUCGestureSettings()
        s.naturalScrolling = ScrollDirection == .Natural
        s.scrollMomentum = ScrollMomentum
        s.secondaryClick = SecondaryClick
        s.lookUp = LookUp
        s.zoom = Zoom
        s.smartZoom = SmartZoom
        s.rotate = Rotate
        s.swipeBetweenPages = SwipeBetweenPages
        switch PagesTrigger {
        case .TwoFingerScroll: s.pagesTrigger = .twoFingerScroll
        case .TwoOrThreeFingerSwipe: s.pagesTrigger = .twoOrThreeFingerSwipe
        case .ThreeFingerSwipe: s.pagesTrigger = .threeFingerSwipe
        }
        s.swipeBetweenFullScreenApps = SwipeBetweenDesktops
        s.fullScreenAppsFingers = DesktopsFingers.count
        s.missionControl = MissionControl
        s.appExpose = AppExpose
        s.missionControlFingers = MissionControlFingers.count
        s.launchpad = Launchpad
        s.showDesktop = ShowDesktop
        s.notificationCenter = NotificationCenter
        return s
    }
}

extension TouchUp {

    /// The saved gestures; before there were any, the separate keys an earlier build of this fork saved, else the defaults.
    static func loadGestureSettings(from defaults: UserDefaults) -> GestureSettings {
        if let data = defaults.data(forKey: gestureSettingsKey),
           let saved = try? JSONDecoder().decode(GestureSettings.self, from: data) {
            return saved
        }

        var s = GestureSettings()
        guard defaults.object(forKey: "gesture.zoom") != nil else { return s }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        func fingers(_ key: String) -> SwipeFingerCount { defaults.integer(forKey: key) == 3 ? .Three : .Four }
        s.ScrollDirection = bool("gesture.naturalScrolling", true) ? .Natural : .Standard
        s.ScrollMomentum = bool("gesture.scrollMomentum", s.ScrollMomentum)
        s.SecondaryClick = bool("gesture.secondaryClick", s.SecondaryClick)
        s.LookUp = bool("gesture.lookUp", s.LookUp)
        s.Zoom = bool("gesture.zoom", s.Zoom)
        s.SmartZoom = bool("gesture.smartZoom", s.SmartZoom)
        s.Rotate = bool("gesture.rotate", s.Rotate)
        s.SwipeBetweenPages = bool("gesture.swipeBetweenPages", s.SwipeBetweenPages)
        s.PagesTrigger = [0: .TwoFingerScroll, 1: .ThreeFingerSwipe, 2: .TwoOrThreeFingerSwipe][defaults.integer(forKey: "gesture.pagesTrigger")] ?? s.PagesTrigger
        s.SwipeBetweenDesktops = bool("gesture.swipeBetweenFullScreenApps", s.SwipeBetweenDesktops)
        s.DesktopsFingers = fingers("gesture.fullScreenAppsFingers")
        s.MissionControl = bool("gesture.missionControl", s.MissionControl)
        s.AppExpose = bool("gesture.appExpose", s.AppExpose)
        s.MissionControlFingers = fingers("gesture.missionControlFingers")
        s.Launchpad = bool("gesture.launchpad", s.Launchpad)
        s.ShowDesktop = bool("gesture.showDesktop", s.ShowDesktop)
        s.NotificationCenter = bool("gesture.notificationCenter", s.NotificationCenter)
        s.linkExposeFingers()
        return s
    }
}


// MARK: - Per-Digitizer Screen Mapping
extension TouchUp {

    private static let digitizerConfigsKey = "digitizerConfigs"

    /// The screen a freshly connected (or unmatched) digitizer maps to by default: the one
    /// that connected most recently, falling back to the last screen in the arrangement.
    var newestScreen: TUCScreen? {
        if let id = idOfLastAddedScreen, let screen = connectedScreens.first(where: { $0.id == id }) {
            return screen
        }
        return connectedScreens.last
    }

    /// Resolves the stored screen identity of a digitizer against the currently connected
    /// screens. Priority: UUID (exact) → display ID (fallback) → most recent screen (implicit).
    func resolvedMapping(forLocationID locationID: HIDLocationID) -> (screen: TUCScreen?, match: ScreenMatch) {
        let config = digitizerConfigs[locationID]

        if let uuid = config?.screenUUID,
           let screen = connectedScreens.first(where: { $0.uuid == uuid }) {
            return (screen, .exact)
        }

        if let id = config?.screenID,
           let screen = connectedScreens.first(where: { $0.id == id }) {
            return (screen, .idFallback)
        }

        if let screen = newestScreen {
            return (screen, .implicit)
        }

        return (nil, .unmapped)
    }

    /// Explicitly assigns a screen to a digitizer (user action) and persists it immediately.
    /// Storing the UUID makes the mapping confirmed, so it survives rearrange/rotate/mirror.
    func assignScreen(_ screen: TUCScreen?, toDigitizer locationID: HIDLocationID) {
        guard var config = digitizerConfigs[locationID] else { return }
        config.screenUUID = screen?.uuid
        config.screenID = screen.map { UInt($0.id) }
        digitizerConfigs[locationID] = config
        persistMapping(forLocationID: locationID)
    }

    /// Sets the additional digitizer rotation (user action) and persists it immediately.
    func setRotation(_ rotation: CGFloat, forDigitizer locationID: HIDLocationID) {
        guard var config = digitizerConfigs[locationID] else { return }
        config.additionalRotation = rotation
        digitizerConfigs[locationID] = config
        persistMapping(forLocationID: locationID)
    }

    /// Sets the touchscreen's real diagonal (user action; nil = use the size the display reports) and persists it.
    func setScreenDiagonal(_ inches: Double?, forDigitizer locationID: HIDLocationID) {
        guard var config = digitizerConfigs[locationID] else { return }
        config.screenDiagonalInches = inches
        digitizerConfigs[locationID] = config
        persistMapping(forLocationID: locationID)
    }

    /// The diagonal the display itself reports (EDID), in inches, or nil if it reports none.
    func reportedDiagonalInches(forDigitizer locationID: HIDLocationID) -> Double? {
        guard let size = resolvedMapping(forLocationID: locationID).screen?.nativePhysicalSize,
              size.width > 0, size.height > 0 else { return nil }
        return Double(hypot(size.width, size.height)) / 25.4
    }

    /// Freezes the currently resolved screen (id + uuid) and rotation of one digitizer into
    /// persistent storage. Covers both cases: an explicit user edit, and an implicit mapping
    /// that worked fine and should stick (called for all digitizers before the window closes).
    func persistMapping(forLocationID locationID: HIDLocationID) {
        guard var config = digitizerConfigs[locationID] else { return }

        // Promote an as-yet-unconfirmed mapping (no stored UUID) to its currently resolved
        // screen — this is the "implicit mapping was fine, freeze it" case. A config that
        // already carries a UUID is a confirmed preference and is never overwritten here: if
        // its panel is merely absent right now (`.idFallback` / `.unmapped`) the stored UUID
        // must survive and reassert via an exact match once the panel returns.
        if config.screenUUID == nil, let screen = resolvedMapping(forLocationID: locationID).screen {
            config.screenID = UInt(screen.id)
            config.screenUUID = screen.uuid
        }

        digitizerConfigs[locationID] = config
        persistedConfigs[locationID] = config
        saveDigitizerConfigs()
    }

    /// Persists the mapping of every currently connected digitizer. Call before the settings
    /// window closes / on termination so implicit mappings become explicit next launch.
    func persistAllDigitizerMappings() {
        for locationID in digitizerConfigs.keys {
            persistMapping(forLocationID: locationID)
        }
    }

    /// Recomputes `connectionState` from the connected digitizers and their resolvable screens.
    func updateConnectionState() {
        guard !connectedDigitizers.isEmpty else {
            connectionState = .disconnected
            return
        }
        let anyResolved = connectedDigitizers.contains {
            resolvedMapping(forLocationID: $0.locationID).screen != nil
        }
        connectionState = anyResolved ? .connectedPreferred : .uncertain
    }

    func loadDigitizerConfigs() {
        guard let data = UserDefaults.standard.data(forKey: Self.digitizerConfigsKey),
              let decoded = try? JSONDecoder().decode([String: DigitizerConfig].self, from: data)
        else { return }

        // JSON object keys are strings; map them back to numeric location IDs.
        persistedConfigs = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            HIDLocationID(key).map { ($0, value) }
        })
    }

    private func saveDigitizerConfigs() {
        let encodable = Dictionary(uniqueKeysWithValues: persistedConfigs.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: Self.digitizerConfigsKey)
        }
    }
}



extension TouchUp: TUCTouchDelegate {
    
    func touchesDidChange() {
        self.touches = self.touchManager.touchSet.allObjects as! [TUCTouch]
    }
    
    
    func touchscreen(forLocationID locationID: UInt32) -> TUCScreen? {
        resolvedMapping(forLocationID: locationID).screen
    }

    func digitizerRotation(forLocationID locationID: UInt32) -> CGFloat {
        digitizerConfigs[locationID]?.additionalRotation ?? 0
    }

    func physicalSize(forLocationID locationID: UInt32) -> CGSize {
        // The user's diagonal, split by the screen's current aspect ratio (points are square).
        guard let inches = digitizerConfigs[locationID]?.screenDiagonalInches, inches > 0,
              let frame = resolvedMapping(forLocationID: locationID).screen?.frame,
              frame.width > 0, frame.height > 0 else { return .zero }
        let diagonalMM = inches * 25.4
        let scale = diagonalMM / Double(hypot(frame.width, frame.height))
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }
    
    func touchscreenDidConnect(withLocationID locationID: UInt32) {
        self.connectedDigitizers.append(Digitizer(locationID: locationID))

        // Restore a previously persisted config for this digitizer, or start a blank one
        // (which resolves implicitly to the most recently added screen).
        if digitizerConfigs[locationID] == nil {
            digitizerConfigs[locationID] = persistedConfigs[locationID] ?? DigitizerConfig()
        }

        updateConnectionState()
    }

    func touchscreenDidDisconnect(withLocationID locationID: UInt32) {
        if let index = self.connectedDigitizers.firstIndex(where: {$0.locationID == locationID}) {
            self.connectedDigitizers.remove(at: index)
        }
        // Drop the live config; the persisted copy in `persistedConfigs` survives for reconnect.
        digitizerConfigs[locationID] = nil

        updateConnectionState()
    }
    
}


extension TouchUp {
    func uiLabels<T>(for keyPath: KeyPath<TouchUp, T>) -> (title:String, description:String) {
        switch keyPath {
        case \.isPublishingMouseEventsEnabled:
            return("Control Mouse with Touch",
                   "Turns the driver on or off.")
            
        case \.longPressDuration:
            return("Press and Hold Delay",
                   "How long one finger has to rest on the screen before it presses the mouse button, for menus that open on press and hold. Moving the finger presses it at once.")

        case \.dragThreshold:
            return("Drag Threshold",
                   "How far (mm) one finger has to move before it drags. Lifting before that is a click. Increase it if taps turn into small drags.")

        case \.doubleClickDistance:
            return("Double Click Zone",
                   "How many mm can two taps be apart from each other to qualify double click")

        case \.edgeDeadZone:
            return("Edge Dead Zone",
                   "Increase this value, to prevent touches from triggering mouse events at the screen edge.")

        case \.ignoreOriginTouches:
            return("Ignore Origin Touches",
                   "If your touchscreen randomly sends coordinate (0,0) in its datastream, toggle this option to make input more stable.")
            
        case \.errorResistance:
            return("Error Resistance",
                   "If your touchscreen is really unreliable at reporting touches, increase this slider to make inputs more stable at the cost of higher latency in detecting liftoffs.")
            
        case \.isExclusiveAccessEnabled:
            return("Exclusive Access",
                   "This option should mitigate undesired mouse events created on some devices.")
        
        case \.areAdditionalDigitizerRotationSettingsVisible:
            return("Digitizer Rotation",
                   "Adds a rotation control to each touchscreen. Only needed if the digitizer orientation in does not match your screen.")
            
        default:
            return("\(keyPath)", "")
        }
    }
}


enum ConnectionState: Int {
    case uncertain
    case disconnected
    case connectedHotPlug // connected as result from hot plugging within a few seconds
    case connectedPreferred // connected with stored cues matching perfectly
    
    var image: NSImage? {
        let image: NSImage?
        
        switch self {
        case .uncertain:
            image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
        case .disconnected:
            image = NSImage(systemSymbolName: "rectangle.badge.xmark", accessibilityDescription: nil)
        default:
            image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: nil)
        }
        
        image?.isTemplate = true
        
        return image
    }
    
    var isConnected: Bool {
        return self == .connectedPreferred || self == .connectedHotPlug
    }
}


extension TUCScreen: @retroactive Identifiable {}


// MARK: - Changing Settings from the Settings Window
//
// The settings window's engine, as T650Native's Engine.swift is for its window: settings are read and changed by name, and
// a change that would move another setting (a gesture moved off a trigger it clashed with or turned off, App Exposé
// following Mission Control's finger count) waits for the user to confirm it.

/// A change that moves other settings too: the change, and each setting it moves, with what it is now and what it becomes.
struct SettingsConfirmation: Identifiable {
    struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let from: String
        let to: String
    }

    let id = UUID()
    let change: Row
    let others: [Row]
    fileprivate let changes: [(name: String, value: SettingValue)]
}

extension TouchUp {

    /// Touch Up's own settings that the catalog shows beside the gestures.
    private static let parameterNames: Set<String> = ["DoubleClickDistance", "DragThreshold", "LongPressDuration"]

    /// A setting's value by name: a gesture setting, or one of the click and drag parameters.
    func value(_ name: String) -> SettingValue? {
        switch name {
        case "DoubleClickDistance": return .double(Double(doubleClickDistance))
        case "DragThreshold": return .double(Double(dragThreshold))
        case "LongPressDuration": return .double(longPressDuration)
        default: return gestures[name]
        }
    }

    /// Sets a setting, asking first if that would move other settings.
    func set(_ name: String, to value: SettingValue) {
        if Self.parameterNames.contains(name) {
            guard let number = value.double else { return }
            switch name {
            case "DoubleClickDistance": doubleClickDistance = CGFloat(number)
            case "DragThreshold": dragThreshold = CGFloat(number)
            default: longPressDuration = number
            }
            return
        }
        guard gestures[name] != value else { return }
        request([(name, value)])
    }

    /// A gesture with a method, as one choice: nil is Off. Otherwise the method is set, then the gesture turned on, in that
    /// order and as one change (so turning it on resolves its clashes for the method just chosen).
    func choose(toggle: String, method: String, value: String?) {
        var changes: [(name: String, value: SettingValue)] = []
        if let value {
            if gestures[method] != .string(value) { changes.append((method, .string(value))) }
            if gestures[toggle]?.bool != true { changes.append((toggle, .bool(true))) }
        } else if gestures[toggle]?.bool == true {
            changes.append((toggle, .bool(false)))
        }
        if !changes.isEmpty { request(changes) }
    }

    /// Makes the changes at once if they move nothing else; otherwise asks first.
    private func request(_ changes: [(name: String, value: SettingValue)]) {
        let preview = gestures.applying(changes).settings
        let asked = Set(changes.map(\.name))
        let moved = GestureSettings.names.filter { !asked.contains($0) && gestures[$0] != preview[$0] }

        let mine = SettingsCatalog.groups(containing: asked)
        let others = SettingsCatalog.groups(containing: moved).filter { group in !mine.contains { $0.id == group.id } }
        guard let first = mine.first, !others.isEmpty else {
            gestures = preview
            return
        }

        let now: (String) -> SettingValue? = { self.value($0) }
        let after: (String) -> SettingValue? = { preview[$0] ?? self.value($0) }
        func row(_ group: SettingGroup) -> SettingsConfirmation.Row {
            SettingsConfirmation.Row(id: group.id, symbol: group.symbol, title: group.title,
                                     from: SettingsCatalog.describe(group, in: now), to: SettingsCatalog.describe(group, in: after))
        }
        confirmation = SettingsConfirmation(change: row(first), others: others.map(row), changes: changes)
    }

    func confirmSettingsChange() {
        guard let pending = confirmation else { return }
        confirmation = nil
        gestures = gestures.applying(pending.changes).settings
    }

    func cancelSettingsChange() {
        confirmation = nil
    }

    /// Every gesture, click and drag setting back to its default. Touchscreen settings are kept.
    func resetSettingsToDefaults() {
        gestures = .defaults
        doubleClickDistance = 8
        dragThreshold = 3
        longPressDuration = 0.5
        showSettingsNote("Settings reset to their defaults.")
    }

    func showSettingsNote(_ note: String) {
        settingsNote = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.settingsNote == note { self?.settingsNote = nil }
        }
    }
}
