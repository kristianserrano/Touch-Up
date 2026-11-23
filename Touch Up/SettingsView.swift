//
//  SettingsView.swift
//  Touch Up
//
//  The settings window: a port of the T650Native project's native settings window
//  (native/SettingsApp/Sources/T650Settings/SettingsViews.swift). A sidebar of panes; in each, the settings as cards with a
//  summary of how they are set, and the selected one in full beside them with its animation. Magic Touch Up's own touchscreen
//  settings have a pane of their own.
//

import SwiftUI
import TouchUpCore

struct SettingsView: View {
    @ObservedObject var model: TouchUp
    @State private var selection: SettingsPane?
    @State private var confirmingReset = false

    var body: some View {
        NavigationSplitView {
            List(SettingsCatalog.panes, selection: shownPane) { pane in
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.symbol)
                }
            }
            .safeAreaInset(edge: .bottom) { AboutFooter() }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem {
                        Button("Reset to Defaults…") { confirmingReset = true }
                    }
                }
                .confirmationDialog("Reset All Settings to Their Defaults?", isPresented: $confirmingReset) {
                    Button("Reset to Defaults", role: .destructive) { model.resetSettingsToDefaults() }
                } message: {
                    Text("Every gesture, click and drag setting goes back to how it was when Magic Touch Up was first installed. Touchscreen settings are kept.")
                }
        }
        .overlay(alignment: .bottom) {
            if let note = model.settingsNote {
                Text(note)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4, y: 1)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.settingsNote)
        // A change that moves other settings: say which, from what and to what, and make it only if confirmed.
        .sheet(item: Binding(get: { model.confirmation }, set: { if $0 == nil { model.cancelSettingsChange() } })) { confirmation in
            ConfirmationSheet(model: model, confirmation: confirmation)
        }
        .frame(minWidth: SettingsWindowSize.minimum.width, minHeight: SettingsWindowSize.minimum.height)
    }

    /// The first pane until another is chosen; Touchscreens first while the app cannot post events yet.
    private var shownPane: Binding<SettingsPane?> {
        Binding(get: {
            selection ?? (model.isAccessibilityAccessGranted
                ? SettingsCatalog.panes.first
                : SettingsCatalog.panes.first { $0.id == SettingsCatalog.touchscreensPaneID })
        }, set: { selection = $0 })
    }

    @ViewBuilder
    private var detail: some View {
        if let pane = shownPane.wrappedValue {
            Group {
                if pane.id == SettingsCatalog.touchscreensPaneID {
                    TouchscreensPane(model: model)
                } else {
                    PaneView(model: model, pane: pane)
                }
            }
            .id(pane.id)
            .navigationTitle(pane.title)
        }
    }
}

/// The settings window's size when it first opens, and the smallest it can be made.
enum SettingsWindowSize {
    static let initial = CGSize(width: 960, height: 560)
    static let minimum = CGSize(width: 900, height: 480)
}

// The sizes the views share.
private enum Layout {
    static let cardColumnWidth: CGFloat = 280
    static let cardSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 10
    static let cardCornerRadius: CGFloat = 8
    static let cardSelectedFillOpacity = 0.18
    static let iconWidth: CGFloat = 20
    static let iconSpacing: CGFloat = 10
    static let glyphMaxWidth: CGFloat = 280
    static let glyphMaxHeight: CGFloat = 220
    static let sheetWidth: CGFloat = 440
}

/// A pane: the settings as cards on the left, each with a summary of how it is set, and on the right the selected one in
/// full (its name and explanation, its switch or choice, its other controls and note) with its animation beneath. Only
/// for a catalog pane, which has at least one card.
struct PaneView: View {
    @ObservedObject var model: TouchUp
    let pane: SettingsPane
    @State private var selected: String?

    private var current: SettingGroup {
        pane.groups.first { $0.id == selected } ?? pane.groups[0]
    }

    var body: some View {
        let settings: (String) -> SettingValue? = { model.value($0) }
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Layout.cardSpacing) {
                    ForEach(pane.groups) { group in
                        SettingCard(group: group, summary: SettingsCatalog.summary(group, in: settings), isSelected: group.id == current.id) {
                            selected = group.id
                        }
                    }
                }
                .padding(12)
            }
            .frame(width: Layout.cardColumnWidth)

            Divider()

            Form {
                GroupSection(model: model, group: current)
                if let glyph = SettingsCatalog.glyph(for: current, in: settings) {
                    Section {
                        GestureGlyphView(glyph: glyph, offLabel: SettingsCatalog.offLabel)
                            .frame(maxWidth: Layout.glyphMaxWidth, maxHeight: Layout.glyphMaxHeight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// A setting's icon, as every row draws it.
struct SettingIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(.tint)
            .frame(width: Layout.iconWidth)
    }
}

/// An icon, a title in bold and a line under it: a card, and a row of the confirmation.
struct IconTitleRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var subtitleFont: Font = .body
    var subtitleLines: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.iconSpacing) {
            SettingIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(subtitleLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A group's heading in the form: its icon, a title, and its explanation under it (as System Settings labels a setting).
struct GroupHeading: View {
    let title: String
    let group: SettingGroup

    var body: some View {
        Label {
            Text(title)
            Text(group.text)
        } icon: {
            Image(systemName: group.symbol)
                .foregroundStyle(.tint)
        }
    }
}

/// A setting as a card: its icon, its name and how it is set now. Selecting it shows it in full beside the cards.
struct SettingCard: View {
    let group: SettingGroup
    let summary: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
        Button(action: select) {
            IconTitleRow(symbol: group.symbol, title: group.title, subtitle: summary, subtitleFont: .callout, subtitleLines: 2)
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(isSelected ? Color.accentColor.opacity(Layout.cardSelectedFillOpacity) : Color(nsColor: .controlBackgroundColor)))
                .overlay(shape.strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 0.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One group, as System Settings draws a setting: a switch (or a title) with its explanation under it, then its method,
/// then a note.
struct GroupSection: View {
    @ObservedObject var model: TouchUp
    let group: SettingGroup

    var body: some View {
        Section {
            if let toggle = group.toggle, let method = group.method {
                Picker(selection: choice(toggle: toggle, method: method.name)) {
                    Text(group.offLabel).tag(String?.none)
                    Divider()
                    ForEach(method.options) { option in
                        Text(option.label).tag(Optional(option.value))
                    }
                } label: {
                    GroupHeading(title: group.title, group: group)
                }
            } else {
                if let toggle = group.toggle {
                    Toggle(isOn: boolBinding(toggle)) { GroupHeading(title: group.title, group: group) }
                } else {
                    GroupHeading(title: group.title, group: group)
                }

                // The controls under a switch work only while it is on.
                let usable = group.toggle.map { model.value($0)?.bool ?? false } ?? true
                ForEach(group.controls) { control in
                    ControlRow(model: model, control: control)
                        .disabled(!usable)
                }
            }
        } footer: {
            if let note = group.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func boolBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { model.value(name)?.bool ?? false }, set: { model.set(name, to: .bool($0)) })
    }

    /// Off while the gesture is off, else its method.
    private func choice(toggle: String, method: String) -> Binding<String?> {
        Binding(
            get: { model.value(toggle)?.bool == true ? model.value(method)?.string : nil },
            set: { model.choose(toggle: toggle, method: method, value: $0) })
    }
}

struct ControlRow: View {
    @ObservedObject var model: TouchUp
    let control: Control

    var body: some View {
        switch control {
        case .measure(let name, let label, let range, let step, let format):
            let value = model.value(name)?.double ?? range.lowerBound
            Slider(value: Binding(get: { value }, set: { model.set(name, to: .double($0)) }), in: range, step: step) {
                Text(label)
                Text(String(format: format, value))
            }

        case .toggle(let name, let label, let text):
            Toggle(isOn: Binding(get: { model.value(name)?.bool ?? false }, set: { model.set(name, to: .bool($0)) })) {
                Text(label)
                if let text { Text(text) }
            }

        case .picker(let name, let label, let options):
            Picker(label, selection: Binding(get: { model.value(name)?.string ?? options[0].value }, set: { model.set(name, to: .string($0)) })) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }
}

/// The confirmation for a change that moves other settings: the change, then each setting it moves, each as its icon, its
/// name and "from → to".
struct ConfirmationSheet: View {
    @ObservedObject var model: TouchUp
    let confirmation: SettingsConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Setting Changes")
                .font(.headline)

            section("You're changing:", [confirmation.change])
            section(confirmation.others.count == 1 ? "This also changes:" : "This also changes these settings:", confirmation.others)

            Text("Continue with changes?")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelSettingsChange() }
                    .keyboardShortcut(.cancelAction)
                Button("Change") { model.confirmSettingsChange() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: Layout.sheetWidth)
    }

    private func section(_ heading: String, _ rows: [SettingsConfirmation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                IconTitleRow(symbol: row.symbol, title: row.title, subtitle: "\(row.from) → \(row.to)")
                    .accessibilityElement(children: .combine)
            }
        }
    }
}


/// The app's version, the credit to the project it is based on, and links to both, at the bottom of the sidebar.
struct AboutFooter: View {
    var body: some View {
        VStack(spacing: 3) {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Magic Touch Up v\(version)")
                    .fontWeight(.semibold)
            }
            Text("Based on Touch Up by Sebastian Hueber")
            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/kristianserrano/Touch-Up")!) {
                    Label("Source", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/shueber/Touch-Up")!) {
                    Label("Original", systemImage: "link")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}



#Preview {
    SettingsView(model: TouchUp())
}
