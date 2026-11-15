import SwiftUI

/// Main settings view using macOS native Settings scene.
struct SettingsView: View {
    var engine: PlaybackEngine?

    var body: some View {
        TabView {
            GeneralSettingsView(engine: engine)
                .tabItem { Label("General", systemImage: "gear") }

            PlaybackSettingsView(engine: engine)
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
    var engine: PlaybackEngine?

    @AppStorage(AppSettings.resumePlayback.key) private var resumePlayback = AppSettings.resumePlayback.defaultValue
    @AppStorage(AppSettings.autoPlayOnOpen.key) private var autoPlayOnOpen = AppSettings.autoPlayOnOpen.defaultValue
    @AppStorage(AppSettings.preventSleep.key) private var preventSleep = AppSettings.preventSleep.defaultValue

    var body: some View {
        Form {
            Section("Playback Behavior") {
                Toggle("Resume playback from last position", isOn: $resumePlayback)
                Toggle("Auto-play when opening a file", isOn: $autoPlayOnOpen)
                Toggle("Prevent sleep during playback", isOn: $preventSleep)
                    // Applies to the file that is playing right now, too.
                    .onChange(of: preventSleep) { engine?.updateSleepPrevention() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Playback Settings

struct PlaybackSettingsView: View {
    var engine: PlaybackEngine?

    @AppStorage(AppSettings.startAtDefaultVolume.key) private var startAtDefaultVolume = AppSettings.startAtDefaultVolume.defaultValue
    @AppStorage(AppSettings.defaultVolume.key) private var defaultVolume = AppSettings.defaultVolume.defaultValue
    @AppStorage(AppSettings.seekSmallStep.key) private var seekSmallStep = AppSettings.seekSmallStep.defaultValue
    @AppStorage(AppSettings.seekLargeStep.key) private var seekLargeStep = AppSettings.seekLargeStep.defaultValue
    @AppStorage(AppSettings.hardwareDecoding.key) private var hardwareDecoding = AppSettings.hardwareDecoding.defaultValue

    var body: some View {
        Form {
            Section("Audio") {
                // Off, the player launches at the volume the last session ended with.
                Toggle("Always start at the default volume", isOn: $startAtDefaultVolume)

                HStack {
                    Text("Default Volume")
                    Slider(value: $defaultVolume, in: 0...1)
                    Text("\(Int(defaultVolume * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .disabled(!startAtDefaultVolume)
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
                    // Applies to the file that is playing right now, too.
                    .onChange(of: hardwareDecoding) { engine?.applyHardwareDecodingSetting() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage(AppSettings.controlBarOpacity.key) private var controlBarOpacity = AppSettings.controlBarOpacity.defaultValue
    @AppStorage(AppSettings.controlsAutoHideDelay.key) private var controlsAutoHideDelay = AppSettings.controlsAutoHideDelay.defaultValue
    @AppStorage(AppSettings.osdDuration.key) private var osdDuration = AppSettings.osdDuration.defaultValue

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
