//
//  TouchUp.swift
//  Touch Up
//
//  The app's model: the touch manager, the settings (gestures, click and drag parameters, each touchscreen's screen,
//  size and rotation), and the touchscreen delegate. The settings window's engine is in SettingsEngine.swift.
//
//  Created by Sebastian Hueber on 03.02.23.
//

import AppKit
import Combine
import TouchUpCore

class TouchUp: NSObject, ObservableObject {
    
    let touchManager: TUCTouchInputManager
    @Published var touches = [TUCTouch]()
    
    
    /// The subscriptions that hand each parameter to the touch manager and save it.
    private var observers = [AnyCancellable]()
    
    @Published var isPublishingMouseEventsEnabled = true
    
    @Published var connectionState: ConnectionState = .disconnected
    
    @Published var longPressDuration = ParameterDefaults.longPressDuration     // s one finger rests before it presses
    @Published var dragThreshold = ParameterDefaults.dragThreshold             // mm one finger travels before it drags
    @Published var doubleClickDistance = ParameterDefaults.doubleClickDistance // mm two taps may be apart to double-click
    @Published var edgeDeadZone = ParameterDefaults.edgeDeadZone               // pt along the screen edges never posted
    @Published var errorResistance = ParameterDefaults.errorResistance         // reports to wait before cancelling a touch
    @Published var ignoreOriginTouches = ParameterDefaults.ignoreOriginTouches
    @Published var isExclusiveAccessEnabled = ParameterDefaults.isExclusiveAccessEnabled

    /// The trackpad gestures (named and ruled as in T650Native). Every change goes to the touch manager and is saved at once.
    @Published var gestures = GestureSettings() {
        didSet {
            touchManager.gestureSettings = gestures.core
            if let data = try? JSONEncoder().encode(gestures) {
                UserDefaults.standard.set(data, forKey: Self.gestureSettingsKey)
            }
        }
    }
    static let gestureSettingsKey = "gestureSettings"

    /// A change that moves other settings too, waiting for the user to confirm it (see SettingsEngine.swift).
    @Published var confirmation: SettingsConfirmation?
    /// A short note at the bottom of the settings window (a reset done), cleared after a few seconds.
    @Published var settingsNote: String?


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


// MARK: - Parameters

/// Magic Touch Up's own settings beside the gestures, and their defaults: one place for the property values, the
/// registered defaults and Reset to Defaults.
enum ParameterDefaults {
    static let longPressDuration: TimeInterval = 0.5
    static let dragThreshold: CGFloat = 3
    static let doubleClickDistance: CGFloat = 8
    static let edgeDeadZone: CGFloat = 0
    static let errorResistance: NSInteger = 4
    static let ignoreOriginTouches = true
    static let isExclusiveAccessEnabled = false
}

extension TouchUp {

    /// The keys the parameters are saved under.
    private enum Key {
        static let longPressDuration = "longPressDuration"
        static let dragThreshold = "dragThreshold"
        static let doubleClickDistance = "doubleClickDistance"
        static let edgeDeadZone = "edgeDeadZone"
        static let errorResistance = "errorResistance"
        static let ignoreOriginTouches = "ignoreOriginTouches"
        static let isExclusiveAccessEnabled = "isExclusiveAccessEnabled"
    }

    /// Loads the saved settings, hands them to the touch manager, and from then on hands over and saves each change.
    func initPreferences() {
        let defaults = UserDefaults.standard

        defaults.register(defaults: [
            Key.longPressDuration: ParameterDefaults.longPressDuration,
            Key.dragThreshold: ParameterDefaults.dragThreshold,
            Key.doubleClickDistance: ParameterDefaults.doubleClickDistance,
            Key.edgeDeadZone: ParameterDefaults.edgeDeadZone,
            Key.errorResistance: ParameterDefaults.errorResistance,
            Key.ignoreOriginTouches: ParameterDefaults.ignoreOriginTouches,
            Key.isExclusiveAccessEnabled: ParameterDefaults.isExclusiveAccessEnabled,
        ])

        longPressDuration = defaults.double(forKey: Key.longPressDuration)
        dragThreshold = defaults.double(forKey: Key.dragThreshold)
        doubleClickDistance = defaults.double(forKey: Key.doubleClickDistance)
        edgeDeadZone = defaults.double(forKey: Key.edgeDeadZone)
        errorResistance = defaults.integer(forKey: Key.errorResistance)
        ignoreOriginTouches = defaults.bool(forKey: Key.ignoreOriginTouches)
        isExclusiveAccessEnabled = defaults.bool(forKey: Key.isExclusiveAccessEnabled)

        /// Saves every change after the current value (which was just loaded).
        func save<Value>(_ publisher: Published<Value>.Publisher, _ key: String) -> AnyCancellable {
            publisher.dropFirst().sink { defaults.set($0, forKey: key) }
        }

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
            },

            save($longPressDuration, Key.longPressDuration),
            save($dragThreshold, Key.dragThreshold),
            save($doubleClickDistance, Key.doubleClickDistance),
            save($edgeDeadZone, Key.edgeDeadZone),
            save($errorResistance, Key.errorResistance),
            save($ignoreOriginTouches, Key.ignoreOriginTouches),
            save($isExclusiveAccessEnabled, Key.isExclusiveAccessEnabled),
        ]

        gestures = Self.loadGestureSettings(from: defaults)
    }

    /// The click and drag parameters back to their defaults (the touchscreen options are kept).
    func resetParametersToDefaults() {
        doubleClickDistance = ParameterDefaults.doubleClickDistance
        dragThreshold = ParameterDefaults.dragThreshold
        longPressDuration = ParameterDefaults.longPressDuration
    }
}


// MARK: - Trackpad Gestures
extension GestureSettings {
    /// The settings as the framework takes them.
    var core: TUCGestureSettings {
        let s = TUCGestureSettings()
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
        return GestureSettings.migratingLegacyKeys { defaults.object(forKey: $0) } ?? GestureSettings()
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

    /// The screen a digitizer is on: its stored screen identity resolved against the connected screens. Priority: UUID
    /// (exact) → display ID (fallback) → most recent screen (implicit). nil when no screen is connected.
    func screen(forDigitizer locationID: HIDLocationID) -> TUCScreen? {
        let config = digitizerConfigs[locationID]

        if let uuid = config?.screenUUID, let screen = connectedScreens.first(where: { $0.uuid == uuid }) {
            return screen
        }
        if let id = config?.screenID, let screen = connectedScreens.first(where: { $0.id == id }) {
            return screen
        }
        return newestScreen
    }

    /// Explicitly assigns a screen to a digitizer (user action) and persists it immediately.
    /// Storing the UUID makes the mapping confirmed, so it survives rearrange/rotate/mirror.
    func assignScreen(_ screen: TUCScreen?, toDigitizer locationID: HIDLocationID) {
        guard var config = digitizerConfigs[locationID] else { return }
        config.screenUUID = screen?.storedUUID
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
        guard let size = screen(forDigitizer: locationID)?.nativePhysicalSize else { return nil }
        return ScreenSize.diagonalInches(of: size)
    }

    /// Freezes the currently resolved screen (id + uuid) and rotation of one digitizer into
    /// persistent storage. Covers both cases: an explicit user edit, and an implicit mapping
    /// that worked fine and should stick (called for all digitizers on quit).
    func persistMapping(forLocationID locationID: HIDLocationID) {
        guard var config = digitizerConfigs[locationID] else { return }

        // Promote an as-yet-unconfirmed mapping (no stored UUID) to its currently resolved
        // screen — this is the "implicit mapping was fine, freeze it" case. A config that
        // already carries a UUID is a confirmed preference and is never overwritten here: if
        // its panel is merely absent right now (resolved only by display ID, or not at all) the stored UUID
        // must survive and reassert via an exact match once the panel returns.
        if config.screenUUID == nil, let screen = screen(forDigitizer: locationID) {
            config.screenID = UInt(screen.id)
            config.screenUUID = screen.storedUUID
        }

        digitizerConfigs[locationID] = config
        persistedConfigs[locationID] = config
        saveDigitizerConfigs()
    }

    /// Persists the mapping of every currently connected digitizer. Called on quit, so implicit mappings become explicit
    /// next launch.
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
            screen(forDigitizer: $0.locationID) != nil
        }
        connectionState = anyResolved ? .connectedPreferred : .uncertain
    }

    func loadDigitizerConfigs() {
        guard let data = UserDefaults.standard.data(forKey: Self.digitizerConfigsKey),
              let decoded = try? JSONDecoder().decode([String: DigitizerConfig].self, from: data)
        else { return }

        // JSON object keys are strings; map them back to numeric location IDs. Earlier versions saved "" for a screen
        // without a UUID, which would match any such screen: it means no UUID, so the display ID decides.
        persistedConfigs = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            var config = value
            if config.screenUUID?.isEmpty == true { config.screenUUID = nil }
            return HIDLocationID(key).map { ($0, config) }
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
        screen(forDigitizer: locationID)
    }

    func digitizerRotation(forLocationID locationID: UInt32) -> CGFloat {
        digitizerConfigs[locationID]?.additionalRotation ?? 0
    }

    func physicalSize(forLocationID locationID: UInt32) -> CGSize {
        // The user's diagonal, split by the screen's current aspect ratio; .zero (the reported size) when not set.
        guard let inches = digitizerConfigs[locationID]?.screenDiagonalInches, inches > 0,
              let frame = screen(forDigitizer: locationID)?.frame else { return .zero }
        return ScreenSize.visibleArea(diagonalInches: inches, aspect: frame.size)
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


enum ConnectionState: Int {
    case uncertain
    case disconnected
    case connectedPreferred // connected, and at least one touchscreen resolves to a screen
    
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
}


extension TUCScreen: @retroactive Identifiable {
    /// The UUID to store for this screen, or nil when macOS gives it none (TUCScreen's nil UUID arrives as ""), so the
    /// display-ID fallback decides instead of the first screen without one.
    var storedUUID: String? { uuid.isEmpty ? nil : uuid }
}
