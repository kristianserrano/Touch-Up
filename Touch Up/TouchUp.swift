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

    // Trackpad gestures (System Settings > Trackpad). Every change is pushed to the touch manager.
    @Published var naturalScrolling = true { didSet { applyGestureSettings() } }
    @Published var scrollMomentum = true { didSet { applyGestureSettings() } }
    @Published var secondaryClick = true { didSet { applyGestureSettings() } }
    @Published var lookUp = false { didSet { applyGestureSettings() } }
    @Published var zoom = true { didSet { applyGestureSettings() } }
    @Published var smartZoom = true { didSet { applyGestureSettings() } }
    @Published var rotate = true { didSet { applyGestureSettings() } }
    @Published var swipeBetweenPages = true { didSet { applyGestureSettings() } }
    @Published var pagesTrigger: TUCPagesTrigger = .twoFingerScroll {
        didSet {
            // Pages and full-screen apps cannot both be three-finger swipes: the one just changed wins, as in macOS.
            if !isApplyingStoredGestures && pagesTrigger != .twoFingerScroll && fullScreenAppsFingers == 3 { fullScreenAppsFingers = 4 }
            applyGestureSettings()
        }
    }
    @Published var swipeBetweenFullScreenApps = true { didSet { applyGestureSettings() } }
    @Published var fullScreenAppsFingers = 3 {
        didSet {
            if !isApplyingStoredGestures && fullScreenAppsFingers == 3 && pagesTrigger != .twoFingerScroll { pagesTrigger = .twoFingerScroll }
            applyGestureSettings()
        }
    }
    @Published var missionControl = true { didSet { applyGestureSettings() } }
    @Published var appExpose = true { didSet { applyGestureSettings() } }
    @Published var missionControlFingers = 3 { didSet { applyGestureSettings() } }
    @Published var launchpad = true { didSet { applyGestureSettings() } }
    @Published var showDesktop = true { didSet { applyGestureSettings() } }
    @Published var notificationCenter = true { didSet { applyGestureSettings() } }

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

    /// Set while the stored gesture settings are loaded: they are pushed to the touch manager once, at the end, and
    /// the pages / full-screen apps conflict rule is not applied to them.
    private var isApplyingStoredGestures = false


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

            "gesture.naturalScrolling" : true,
            "gesture.scrollMomentum" : true,
            "gesture.secondaryClick" : true,
            "gesture.lookUp" : false,
            "gesture.zoom" : true,
            "gesture.smartZoom" : true,
            "gesture.rotate" : true,
            "gesture.swipeBetweenPages" : true,
            "gesture.pagesTrigger" : TUCPagesTrigger.twoFingerScroll.rawValue,
            "gesture.swipeBetweenFullScreenApps" : true,
            "gesture.fullScreenAppsFingers" : 3,
            "gesture.missionControl" : true,
            "gesture.appExpose" : true,
            "gesture.missionControlFingers" : 3,
            "gesture.launchpad" : true,
            "gesture.showDesktop" : true,
            "gesture.notificationCenter" : true,
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
        
        
        
        isApplyingStoredGestures = true
        naturalScrolling = defaults.bool(forKey: "gesture.naturalScrolling")
        scrollMomentum = defaults.bool(forKey: "gesture.scrollMomentum")
        secondaryClick = defaults.bool(forKey: "gesture.secondaryClick")
        lookUp = defaults.bool(forKey: "gesture.lookUp")
        zoom = defaults.bool(forKey: "gesture.zoom")
        smartZoom = defaults.bool(forKey: "gesture.smartZoom")
        rotate = defaults.bool(forKey: "gesture.rotate")
        swipeBetweenPages = defaults.bool(forKey: "gesture.swipeBetweenPages")
        swipeBetweenFullScreenApps = defaults.bool(forKey: "gesture.swipeBetweenFullScreenApps")
        // The conflict rules are off while loading: the stored pair was already resolved when it was saved.
        pagesTrigger = TUCPagesTrigger(rawValue: defaults.integer(forKey: "gesture.pagesTrigger")) ?? .twoFingerScroll
        fullScreenAppsFingers = defaults.integer(forKey: "gesture.fullScreenAppsFingers") == 4 ? 4 : 3
        missionControl = defaults.bool(forKey: "gesture.missionControl")
        appExpose = defaults.bool(forKey: "gesture.appExpose")
        missionControlFingers = defaults.integer(forKey: "gesture.missionControlFingers") == 4 ? 4 : 3
        launchpad = defaults.bool(forKey: "gesture.launchpad")
        showDesktop = defaults.bool(forKey: "gesture.showDesktop")
        notificationCenter = defaults.bool(forKey: "gesture.notificationCenter")
        isApplyingStoredGestures = false
        applyGestureSettings()

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

        defaults.set(naturalScrolling, forKey: "gesture.naturalScrolling")
        defaults.set(scrollMomentum, forKey: "gesture.scrollMomentum")
        defaults.set(secondaryClick, forKey: "gesture.secondaryClick")
        defaults.set(lookUp, forKey: "gesture.lookUp")
        defaults.set(zoom, forKey: "gesture.zoom")
        defaults.set(smartZoom, forKey: "gesture.smartZoom")
        defaults.set(rotate, forKey: "gesture.rotate")
        defaults.set(swipeBetweenPages, forKey: "gesture.swipeBetweenPages")
        defaults.set(pagesTrigger.rawValue, forKey: "gesture.pagesTrigger")
        defaults.set(swipeBetweenFullScreenApps, forKey: "gesture.swipeBetweenFullScreenApps")
        defaults.set(fullScreenAppsFingers, forKey: "gesture.fullScreenAppsFingers")
        defaults.set(missionControl, forKey: "gesture.missionControl")
        defaults.set(appExpose, forKey: "gesture.appExpose")
        defaults.set(missionControlFingers, forKey: "gesture.missionControlFingers")
        defaults.set(launchpad, forKey: "gesture.launchpad")
        defaults.set(showDesktop, forKey: "gesture.showDesktop")
        defaults.set(notificationCenter, forKey: "gesture.notificationCenter")
        defaults.set(areAdditionalDigitizerRotationSettingsVisible, forKey: "areAdditionalDigitizerRotationSettingsVisible")
    }

}


// MARK: - Trackpad Gestures
extension TouchUp {

    /// Hands the current gesture switches to the touch manager (it keeps a copy).
    func applyGestureSettings() {
        if isApplyingStoredGestures { return }

        let s = TUCGestureSettings()
        s.naturalScrolling = naturalScrolling
        s.scrollMomentum = scrollMomentum
        s.secondaryClick = secondaryClick
        s.lookUp = lookUp
        s.zoom = zoom
        s.smartZoom = smartZoom
        s.rotate = rotate
        s.swipeBetweenPages = swipeBetweenPages
        s.pagesTrigger = pagesTrigger
        s.swipeBetweenFullScreenApps = swipeBetweenFullScreenApps
        s.fullScreenAppsFingers = fullScreenAppsFingers
        s.missionControl = missionControl
        s.appExpose = appExpose
        s.missionControlFingers = missionControlFingers
        s.launchpad = launchpad
        s.showDesktop = showDesktop
        s.notificationCenter = notificationCenter
        touchManager.gestureSettings = s
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
