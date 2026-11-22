//
//  DigitizerMappingView.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 04.06.26.
//

import SwiftUI

struct DigitizerMappingView: View {
    
    @ObservedObject var model: TouchUp
    
    var body: some View {
        if model.connectedDigitizers.isEmpty {
            noDigitizersPlaceholder
        } else {
            ForEach(model.connectedDigitizers) { digitizer in
                digitizerControls(for: digitizer)
            }
        }
    }
    
    
    var noDigitizersPlaceholder: some View {
        VStack(alignment: .center) {
            Image(systemName: "rectangle.slash")
                .font(.largeTitle)
            Text("Upon connecting a touchscreen, it will appear here.")
                .font(.caption)
                
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
    }
    
    
    @ViewBuilder
    private func digitizerControls(for digitizer: Digitizer) -> some View {
        VStack(alignment: .leading) {
            HStack(spacing: 4) {
                Text(digitizer.locationIDString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    let screen = model.resolvedMapping(forLocationID: digitizer.locationID).screen
                    (NSApp.delegate as? AppDelegate)?.showDebugOverlay(on: screen, digitizer: digitizer.locationID)
                }, label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("Test")
                    }
                    .font(.caption)
                })
                .foregroundColor(.accentColor)
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                let current = model.digitizerConfigs[digitizer.locationID]?.additionalRotation ?? 0

                Text(digitizer.deviceName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if model.areAdditionalDigitizerRotationSettingsVisible || current != 0 {
                    rotationPicker(for: digitizer)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrowshape.forward.fill")
                    .foregroundColor(.secondary)

                Spacer(minLength: 8)

                screenPicker(for: digitizer)
            }

            HStack(spacing: 8) {
                Text("Screen size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                sizePicker(for: digitizer)
            }
        }
    }

    /// Gesture distances are in millimetres, so they depend on the screen's real size. Some panels report a wrong one.
    @ViewBuilder
    private func sizePicker(for digitizer: Digitizer) -> some View {
        let current = model.digitizerConfigs[digitizer.locationID]?.screenDiagonalInches ?? 0
        let selection = Binding {
            current
        } set: { inches in
            model.setScreenDiagonal(inches > 0 ? inches : nil, forDigitizer: digitizer.locationID)
        }
        let presets: [Double] = [7, 8, 10.1, 11.6, 13.3, 14, 15.6, 17.3, 19, 21.5, 23.8, 27, 32]
        let reported = model.reportedDiagonalInches(forDigitizer: digitizer.locationID)

        Picker(selection: selection) {
            Text(reported.map { String(format: "As reported (%.1f″)", $0) } ?? "As reported").tag(0.0)
            Divider()
            ForEach(presets, id: \.self) { inches in
                Text(String(format: inches == inches.rounded() ? "%.0f″" : "%.1f″", inches)).tag(inches)
            }
            if current > 0 && !presets.contains(current) {
                Text(String(format: "%.1f″", current)).tag(current)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    @ViewBuilder
    private func screenPicker(for digitizer: Digitizer) -> some View {
        let selection = Binding {
            model.resolvedMapping(forLocationID: digitizer.locationID).screen?.uuid ?? ""
        } set: { uuid in
            model.assignScreen(model.connectedScreens.first { $0.uuid == uuid }, toDigitizer: digitizer.locationID)
        }

        Picker(selection: selection) {
            ForEach(model.connectedScreens) { screen in
                Text(screen.name).tag(screen.uuid)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }


    @ViewBuilder
    private func rotationPicker(for digitizer: Digitizer) -> some View {
        let selection = Binding {
            model.digitizerConfigs[digitizer.locationID]?.additionalRotation ?? 0
        } set: { rotation in
            model.setRotation(rotation, forDigitizer: digitizer.locationID)
        }

        Picker(selection: selection) {
            let rotations: [CGFloat] = [0, 90, 180, 270]
            ForEach(rotations, id: \.self) {
                Text("\(Int($0))°").tag($0)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

}

#Preview {
    DigitizerMappingView(model: TouchUp())
}
