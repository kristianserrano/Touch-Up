//
//  SettingsEngine.swift
//  Touch Up
//
//  The settings window's engine, as T650Native's Engine.swift is for its window: settings are read and changed by name,
//  and a change that would move another setting (a gesture moved off a trigger it clashed with or turned off, App Exposé
//  following Mission Control's finger count) waits for the user to confirm it.
//

import Foundation

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

/// The names the catalog and the engine give Magic Touch Up's own click and drag parameters, beside the gesture settings.
/// (They are saved under the property names, see TouchUp's `Key`, which existing installs already use.)
enum ParameterName {
    static let doubleClickDistance = "DoubleClickDistance"
    static let dragThreshold = "DragThreshold"
    static let longPressDuration = "LongPressDuration"
}

extension TouchUp {

    /// How long a note stays at the bottom of the settings window.
    private static let noteSeconds = 4.0

    /// A setting's value by name: a gesture setting, or one of the click and drag parameters.
    func value(_ name: String) -> SettingValue? {
        switch name {
        case ParameterName.doubleClickDistance: return .double(Double(doubleClickDistance))
        case ParameterName.dragThreshold: return .double(Double(dragThreshold))
        case ParameterName.longPressDuration: return .double(longPressDuration)
        default: return gestures[name]
        }
    }

    /// Sets a setting: a parameter at once; a gesture setting asking first if that would move other settings.
    func set(_ name: String, to value: SettingValue) {
        switch (name, value.double) {
        case (ParameterName.doubleClickDistance, let number?): doubleClickDistance = CGFloat(number)
        case (ParameterName.dragThreshold, let number?): dragThreshold = CGFloat(number)
        case (ParameterName.longPressDuration, let number?): longPressDuration = number
        case (ParameterName.doubleClickDistance, nil), (ParameterName.dragThreshold, nil), (ParameterName.longPressDuration, nil):
            return  // a parameter takes a number; anything else changes nothing
        default:
            guard gestures[name] != value else { return }
            request([(name, value)])
        }
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
        resetParametersToDefaults()
        showSettingsNote("Settings reset to their defaults.")
    }

    func showSettingsNote(_ note: String) {
        settingsNote = note
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.noteSeconds) { [weak self] in
            if self?.settingsNote == note { self?.settingsNote = nil }
        }
    }
}
