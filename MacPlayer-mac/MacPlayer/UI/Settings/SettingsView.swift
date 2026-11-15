import SwiftUI

/// Main settings view using macOS native Settings scene.
struct SettingsView: View {
    var engine: PlaybackEngine?

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            PlaybackSettingsView()
                .tabItem { Label("Playback", systemImage: "play.circle") }

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            if let engine {
                KeyBindingSettingsView(keyBindingManager: engine.keyBindings)
                    .tabItem { Label("Key Bindings", systemImage: "keyboard") }
            }
        }
        .frame(width: 500, height: 450)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("autoPlayOnOpen") private var autoPlayOnOpen = true
    @AppStorage("preventSleep") private var preventSleep = true

    var body: some View {
        Form {
            Section("Playback Behavior") {
                Toggle("Resume playback from last position", isOn: $resumePlayback)
                Toggle("Auto-play when opening a file", isOn: $autoPlayOnOpen)
                Toggle("Prevent sleep during playback", isOn: $preventSleep)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Playback Settings

struct PlaybackSettingsView: View {
    @AppStorage("defaultVolume") private var defaultVolume: Double = 1.0
    @AppStorage("seekSmallStep") private var seekSmallStep: Double = 5.0
    @AppStorage("seekLargeStep") private var seekLargeStep: Double = 30.0
    @AppStorage("hardwareDecoding") private var hardwareDecoding = true

    var body: some View {
        Form {
            Section("Audio") {
                HStack {
                    Text("Default Volume")
                    Slider(value: $defaultVolume, in: 0...1)
                    Text("\(Int(defaultVolume * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("Seeking") {
                HStack {
                    Text("Small Step")
                    Slider(value: $seekSmallStep, in: 1...30, step: 1)
                    Text("\(Int(seekSmallStep))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text("Large Step")
                    Slider(value: $seekLargeStep, in: 10...120, step: 5)
                    Text("\(Int(seekLargeStep))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("Decoding") {
                Toggle("Hardware decoding (VideoToolbox)", isOn: $hardwareDecoding)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("controlBarOpacity") private var controlBarOpacity: Double = 0.8
    @AppStorage("controlsAutoHideDelay") private var controlsAutoHideDelay: Double = 3.0
    @AppStorage("osdDuration") private var osdDuration: Double = 1.5

    var body: some View {
        Form {
            Section("Control Bar") {
                HStack {
                    Text("Opacity")
                    Slider(value: $controlBarOpacity, in: 0.3...1)
                    Text("\(Int(controlBarOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text("Auto-hide Delay")
                    Slider(value: $controlsAutoHideDelay, in: 1...10, step: 0.5)
                    Text("\(String(format: "%.1f", controlsAutoHideDelay))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("OSD") {
                HStack {
                    Text("Display Duration")
                    Slider(value: $osdDuration, in: 0.5...5, step: 0.5)
                    Text("\(String(format: "%.1f", osdDuration))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
