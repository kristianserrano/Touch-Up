//
//  SettingsView.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 03.02.23.
//

import SwiftUI
import TouchUpCore

struct SettingsView: View {
    
    @ObservedObject var model: TouchUp
    
    var welcomeBanner: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Touch Up 🐑")
                    .font(.largeTitle)
                Text("Touch Up converts USB HID data from any Windows certified touchscreen to mouse events.\nInjecting mouse events requires access to accessibility APIs. You can allow this by clicking the button below.")
            }
            
            HStack {
                Spacer()
                Button {
                    model.grantAccessibilityAccess()
                } label: {
                    
                    Text("Grant Accessibility Access")
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
    }
    
    var top: some View {
        Toggle(model.uiLabels(for: \.isPublishingMouseEventsEnabled).title, isOn: $model.isPublishingMouseEventsEnabled)
    }

    
    var pointAndClickSettings: some View {
        Group {
            Toggle(isOn: $model.secondaryClick) {
                SettingsExplanationLabel(labels: ("Secondary Click", "Tap with two fingers."))
            }

            Toggle(isOn: $model.lookUp) {
                SettingsExplanationLabel(labels: ("Look Up & Data Detectors", "Tap with three fingers."))
            }
        }
    }


    var scrollAndZoomSettings: some View {
        Group {
            Toggle(isOn: $model.naturalScrolling) {
                SettingsExplanationLabel(labels: ("Natural Scrolling", "Content tracks your finger movement."))
            }

            Toggle(isOn: $model.scrollMomentum) {
                SettingsExplanationLabel(labels: ("Scroll Momentum", "Keep scrolling for a moment after your fingers lift."))
            }

            Toggle(isOn: $model.zoom) {
                SettingsExplanationLabel(labels: ("Zoom In or Out", "Pinch with two fingers."))
            }

            Toggle(isOn: $model.smartZoom) {
                SettingsExplanationLabel(labels: ("Smart Zoom", "Double-tap with two fingers. A single two-finger tap then waits a moment before its secondary click."))
            }

            Toggle(isOn: $model.rotate) {
                SettingsExplanationLabel(labels: ("Rotate", "Rotate with two fingers."))
            }
        }
    }


    var moreGesturesSettings: some View {
        Group {
            Toggle(isOn: $model.swipeBetweenPages) {
                SettingsExplanationLabel(labels: ("Swipe Between Pages", "Go back and forward in browsers and other apps."))
            }
            Picker("", selection: $model.pagesTrigger) {
                Text("Scroll left or right with two fingers").tag(TUCPagesTrigger.twoFingerScroll)
                Text("Swipe with three fingers").tag(TUCPagesTrigger.threeFingerSwipe)
                Text("Swipe with two or three fingers").tag(TUCPagesTrigger.twoOrThreeFingerSwipe)
            }
            .disabled(!model.swipeBetweenPages)

            Toggle(isOn: $model.swipeBetweenFullScreenApps) {
                SettingsExplanationLabel(labels: ("Swipe Between Full-Screen Apps", "Swipe left or right."))
            }
            Picker("", selection: $model.fullScreenAppsFingers) {
                Text("Three fingers").tag(3)
                Text("Four fingers").tag(4)
            }
            .disabled(!model.swipeBetweenFullScreenApps)

            Toggle(isOn: $model.notificationCenter) {
                SettingsExplanationLabel(labels: ("Notification Center", "Swipe left from the right edge with two fingers."))
            }

            Toggle(isOn: $model.missionControl) {
                SettingsExplanationLabel(labels: ("Mission Control", "Swipe up."))
            }

            Toggle(isOn: $model.appExpose) {
                SettingsExplanationLabel(labels: ("App Exposé", "Swipe down."))
            }
            Picker("", selection: $model.missionControlFingers) {
                Text("Three fingers").tag(3)
                Text("Four fingers").tag(4)
            }
            .disabled(!model.missionControl && !model.appExpose)

            Toggle(isOn: $model.launchpad) {
                SettingsExplanationLabel(labels: ("Launchpad", "Pinch with thumb and three fingers."))
            }

            Toggle(isOn: $model.showDesktop) {
                SettingsExplanationLabel(labels: ("Show Desktop", "Spread with thumb and three fingers."))
            }
        }
    }
    
    
    var parameterSettings: some View {
        Group {
            Slider(value: $model.longPressDuration, in: 0.2...1.5, step: 0.1){
                SettingsExplanationLabel(labels: model.uiLabels(for: \.longPressDuration))
            }

            Slider(value: $model.dragThreshold, in: 1...8, step: 0.5){
                SettingsExplanationLabel(labels: model.uiLabels(for: \.dragThreshold))
            }
            
            Slider(value: $model.doubleClickDistance, in: 0...8, step: 1) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.doubleClickDistance))
            }
        }
    }
    
    
    var troubleshootingSettings: some View {
        Group {
            let errorResistance_ = Binding {Double(model.errorResistance)} set: {
                model.errorResistance = NSInteger(Int($0)) }
            
            Slider(value: errorResistance_ , in: 0...10, step: 1) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.errorResistance))
            }
            
            Slider(value: $model.edgeDeadZone, in: 0...30, step: 5) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.edgeDeadZone))
            }

            Toggle(isOn: $model.ignoreOriginTouches) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.ignoreOriginTouches))
            }

            Toggle(isOn: $model.isExclusiveAccessEnabled) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.isExclusiveAccessEnabled))
            }

            Toggle(isOn: $model.areAdditionalDigitizerRotationSettingsVisible) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.areAdditionalDigitizerRotationSettingsVisible))
            }
        }
    }
    
    
    var footer: some View {
        HStack {
            Spacer()
            VStack {
                if let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Touch Up v\(versionString)")
                        .font(.title2)
                }

                Text("Made with 🐑 in Aachen")
                    .font(.footnote)
                
                Link(destination: URL(string: "https://github.com/shueber/Touch-Up")!, label: {
                    Label("GitHub", systemImage: "link")
                        .foregroundColor(.accentColor)
                })
            }
            .padding(.vertical)
            Spacer()
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        
    }
    
    var container: some View {
        if #available(macOS 13.0, *) {
            return Form {
                if !model.isAccessibilityAccessGranted {
                    Section {
                        welcomeBanner
                    } footer: {
                        Rectangle()
                            .frame(width:0, height:0)
                            .foregroundColor(.clear)
                    }

                }
                
                Section {
                    top
                }

                Section("Touchscreens") {
                    DigitizerMappingView(model: self.model)
                }

                Section("Point & Click") {
                    pointAndClickSettings
                }

                Section("Scroll & Zoom") {
                    scrollAndZoomSettings
                }

                Section("More Gestures") {
                    moreGesturesSettings
                }
                
                Section("Parameters") {
                    parameterSettings
                }

                Section {
                    troubleshootingSettings
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    footer
                }



            }
            .formStyle(.grouped)

        } else {
            return List {
                LegacySection {
                    top
                }

                LegacySection(title: "Touchscreens") {
                    DigitizerMappingView(model: self.model)
                }

                LegacySection(title: "Point & Click") {
                    pointAndClickSettings
                }

                LegacySection(title: "Scroll & Zoom") {
                    scrollAndZoomSettings
                }

                LegacySection(title: "More Gestures") {
                    moreGesturesSettings
                }
                
                LegacySection(title: "Parameters") {
                    parameterSettings
                }
                
                LegacySection(title: "Troubleshooting") {
                    troubleshootingSettings
                }
                
                footer
                
            }
            .toggleStyle(.switch)
            
        }
    }
    
    
    
    var body: some View {
        container
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 350,  maxHeight: .infinity)
        
    }
}


struct LegacySection<Content: View>: View {
    var title: String? = nil
    var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading) {
            if let title = title {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 12)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .foregroundColor(.secondary.opacity(0.1))
                    .shadow(radius: 1)
                    
                    
                
                VStack(alignment: .leading, spacing: 16, content: content)
                    .padding(12)
            }
            
        }
        .padding(.bottom)
    }
}


struct SettingsExplanationLabel: View {
    
    let labels: (title:String, description:String)
    
    var body: some View {
        VStack(alignment:.leading, spacing: 4) {
            Text(labels.title)
            Text(labels.description)
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}



struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(model: TouchUp())
    }
}
