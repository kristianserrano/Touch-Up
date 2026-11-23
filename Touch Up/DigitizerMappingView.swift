//
//  DigitizerMappingView.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 04.06.26.
//
//  The Touchscreens pane, laid out like System Settings › Displays: the connected displays as a carousel of pictures at
//  the top, the selected one's touch settings in grouped rows under it (which touchscreen is on it, its real size as a
//  list like the resolutions, the touch rotation), and buttons for the touch test and the advanced options at the bottom.
//

import SwiftUI
import TouchUpCore

struct TouchscreensPane: View {
    @ObservedObject var model: TouchUp
    @State private var selectedScreen: String?
    @State private var showingAdvanced = false
    @State private var showingAllSizes = false

    /// The display shown below the carousel: the chosen one, else the first with a touchscreen, else the first.
    private var screen: TUCScreen? {
        model.connectedScreens.first { $0.uuid == selectedScreen }
            ?? model.connectedScreens.first { !digitizers(on: $0).isEmpty }
            ?? model.connectedScreens.first
    }

    var body: some View {
        Form {
            if !model.isAccessibilityAccessGranted {
                Section {
                    accessibilityBanner
                }
            }

            Section {
                DisplayCarousel(model: model, selected: screen?.uuid) { selectedScreen = $0.uuid }
            }

            if let screen {
                Section {
                    Toggle("Control mouse with touch", isOn: $model.isPublishingMouseEventsEnabled)
                    touchscreenPicker(for: screen)
                }

                if let digitizer = digitizers(on: screen).first {
                    Section {
                        sizeList(for: digitizer, on: screen)
                        Toggle("Show all sizes", isOn: $showingAllSizes)
                    } header: {
                        Text("Screen Size")
                    } footer: {
                        Text("Gestures are measured on the glass, so they need the screen's real size. Choose it if the size the display reports is wrong.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        rotationPicker(for: digitizer)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView("No Displays", systemImage: "display.trianglebadge.exclamationmark",
                                           description: Text("Connect a touchscreen to set it up here."))
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Advanced…") { showingAdvanced = true }
                    Button("Test…") {
                        let digitizer = screen.flatMap { digitizers(on: $0).first?.locationID }
                        (NSApp.delegate as? AppDelegate)?.showDebugOverlay(on: screen, digitizer: digitizer)
                    }
                    .disabled(screen == nil)
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAdvanced) {
            AdvancedTouchSheet(model: model)
        }
    }

    // MARK: Rows

    private var accessibilityBanner: some View {
        HStack(alignment: .top) {
            Label {
                Text("Allow Accessibility access")
                Text("Magic Touch Up turns touches into clicks and gestures, which macOS allows only with Accessibility access.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Grant Access…") { model.grantAccessibilityAccess() }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Which touchscreen is on this display (the Displays pane's "Use as" row).
    @ViewBuilder
    private func touchscreenPicker(for screen: TUCScreen) -> some View {
        let here = digitizers(on: screen)
        let selection = Binding<HIDLocationID?> {
            here.first?.locationID
        } set: { locationID in
            if let locationID { model.assignScreen(screen, toDigitizer: locationID) }
        }

        Picker("Touchscreen", selection: selection) {
            if here.isEmpty {
                Text("None").tag(HIDLocationID?.none)
            }
            ForEach(model.connectedDigitizers) { digitizer in
                Text(digitizer.deviceName).tag(Optional(digitizer.locationID))
            }
        }
        .disabled(model.connectedDigitizers.isEmpty)
    }

    /// The real screen sizes to choose from, as the Displays pane lists resolutions: the size the display reports first.
    @ViewBuilder
    private func sizeList(for digitizer: Digitizer, on screen: TUCScreen) -> some View {
        let chosen = model.digitizerConfigs[digitizer.locationID]?.screenDiagonalInches
        let reported = model.reportedDiagonalInches(forDigitizer: digitizer.locationID)
        let sizes = listedSizes(including: chosen)

        VStack(spacing: 0) {
            SizeRow(label: reported.map { String(format: "%.1f″ (Reported)", $0) } ?? "As Reported",
                    detail: physicalLabel(screen.nativePhysicalSize),
                    selected: chosen == nil) {
                model.setScreenDiagonal(nil, forDigitizer: digitizer.locationID)
            }
            ForEach(sizes, id: \.self) { inches in
                SizeRow(label: Self.inchesLabel(inches), detail: physicalLabel(size(inches, on: screen)), selected: chosen == inches) {
                    model.setScreenDiagonal(inches, forDigitizer: digitizer.locationID)
                }
            }
        }
    }

    @ViewBuilder
    private func rotationPicker(for digitizer: Digitizer) -> some View {
        let selection = Binding {
            model.digitizerConfigs[digitizer.locationID]?.additionalRotation ?? 0
        } set: { rotation in
            model.setRotation(rotation, forDigitizer: digitizer.locationID)
        }

        Picker(selection: selection) {
            Text("Standard").tag(CGFloat(0))
            Text("90°").tag(CGFloat(90))
            Text("180°").tag(CGFloat(180))
            Text("270°").tag(CGFloat(270))
        } label: {
            Text("Touch rotation")
            Text("Turn this if touches land in the wrong place after rotating the display or mounting the screen differently.")
        }
    }

    // MARK: Helpers

    /// The common sizes, or every size with Show all sizes, and always the one chosen.
    private func listedSizes(including chosen: Double?) -> [Double] {
        let common: [Double] = [7, 10.1, 13.3, 15.6, 21.5, 23.8, 27, 32]
        let more: [Double] = [8, 11.6, 12.3, 14, 16, 17.3, 19, 24, 34, 43, 55]
        var sizes = showingAllSizes ? (common + more).sorted() : common
        if let chosen, !sizes.contains(chosen) { sizes = (sizes + [chosen]).sorted() }
        return sizes
    }

    private func digitizers(on screen: TUCScreen) -> [Digitizer] {
        model.connectedDigitizers.filter { model.resolvedMapping(forLocationID: $0.locationID).screen?.uuid == screen.uuid }
    }

    /// The visible area of a screen of this diagonal, with this screen's aspect ratio.
    private func size(_ inches: Double, on screen: TUCScreen) -> CGSize {
        let frame = screen.frame.size
        guard frame.width > 0, frame.height > 0 else { return .zero }
        let scale = inches * 25.4 / Double(hypot(frame.width, frame.height))
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }

    private func physicalLabel(_ size: CGSize) -> String {
        size.width > 0 ? String(format: "%.0f × %.0f mm", size.width, size.height) : ""
    }

    static func inchesLabel(_ inches: Double) -> String {
        String(format: inches == inches.rounded() ? "%.0f″" : "%.1f″", inches)
    }
}

/// One row of the size list, as the Displays pane draws a resolution: the chosen one filled.
private struct SizeRow: View {
    let label: String
    let detail: String
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack {
                Text(label)
                Spacer()
                Text(detail)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.clear))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Carousel

/// The connected displays side by side, as pictures with their names under them; a hand marks the ones with a touchscreen,
/// and a caret the one selected.
private struct DisplayCarousel: View {
    @ObservedObject var model: TouchUp
    let selected: String?
    let select: (TUCScreen) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 28) {
                ForEach(model.connectedScreens, id: \.uuid) { screen in
                    let touch = model.connectedDigitizers.contains {
                        model.resolvedMapping(forLocationID: $0.locationID).screen?.uuid == screen.uuid
                    }
                    Button { select(screen) } label: {
                        DisplayThumbnail(screen: screen, hasTouch: touch, isSelected: screen.uuid == selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DisplayThumbnail: View {
    let screen: TUCScreen
    let hasTouch: Bool
    let isSelected: Bool

    private static let height: CGFloat = 72

    var body: some View {
        let aspect = screen.frame.height > 0 ? screen.frame.width / screen.frame.height : 16 / 9
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hue: 0.6, saturation: 0.55, brightness: 0.75),
                                                          Color(hue: 0.72, saturation: 0.45, brightness: 0.95)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .padding(4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2.5 : 1)
                    }

                if hasTouch {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 6, y: 6)
                }
            }
            .frame(width: Self.height * aspect, height: Self.height)

            Text(screen.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            // The caret under the selected display, as in System Settings.
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color(nsColor: .separatorColor))
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(screen.name + (hasTouch ? ", touchscreen" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}


// MARK: - Advanced

/// The troubleshooting options, behind Advanced… as the Displays pane keeps its own.
private struct AdvancedTouchSheet: View {
    @ObservedObject var model: TouchUp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    let errorResistance = Binding { Double(model.errorResistance) } set: { model.errorResistance = NSInteger(Int($0)) }
                    Slider(value: errorResistance, in: 0...10, step: 1) {
                        SettingsExplanationLabel(labels: model.uiLabels(for: \.errorResistance))
                    }
                    Slider(value: $model.edgeDeadZone, in: 0...30, step: 5) {
                        SettingsExplanationLabel(labels: model.uiLabels(for: \.edgeDeadZone))
                    }
                }
                Section {
                    Toggle(isOn: $model.ignoreOriginTouches) {
                        SettingsExplanationLabel(labels: model.uiLabels(for: \.ignoreOriginTouches))
                    }
                    Toggle(isOn: $model.isExclusiveAccessEnabled) {
                        SettingsExplanationLabel(labels: model.uiLabels(for: \.isExclusiveAccessEnabled))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
    }
}
