import Foundation

/// A preference stored in `UserDefaults`: its key, and the value it has until the user changes it.
///
/// The Settings window binds to `key` through `@AppStorage`; the player reads `value`.
/// Keeping both in one place is what makes a control in Settings actually do something.
struct Setting<Value: Sendable>: Sendable {
    let key: String
    let defaultValue: Value

    var value: Value {
        UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue
    }
}

/// Every preference shown in the Settings window.
enum AppSettings {
    // MARK: General

    /// Continue a file from where it was left.
    static let resumePlayback = Setting(key: "resumePlayback", defaultValue: true)
    /// Start playing as soon as a file is opened. Off leaves it paused on its first frame.
    static let autoPlayOnOpen = Setting(key: "autoPlayOnOpen", defaultValue: true)
    /// Keep the display awake while a file is playing.
    static let preventSleep = Setting(key: "preventSleep", defaultValue: true)
    /// Keep the list of recently played files, shown on the start screen and in the Dock menu.
    /// Off, the list is hidden and the files played meanwhile are left out of it.
    static let keepRecentFiles = Setting(key: "keepRecentFiles", defaultValue: true)

    // MARK: Playback

    /// Launch at `defaultVolume` instead of the volume the last session ended with.
    static let startAtDefaultVolume = Setting(key: "startAtDefaultVolume", defaultValue: false)
    static let defaultVolume = Setting(key: "defaultVolume", defaultValue: 1.0)
    /// Seconds skipped by the small and the large seek shortcuts.
    static let seekSmallStep = Setting(key: "seekSmallStep", defaultValue: 5.0)
    static let seekLargeStep = Setting(key: "seekLargeStep", defaultValue: 30.0)
    /// Decode through VideoToolbox when the codec allows it.
    static let hardwareDecoding = Setting(key: "hardwareDecoding", defaultValue: true)

    // MARK: Appearance

    /// Darkness of the gradient behind the control bar, at its bottom edge.
    static let controlBarOpacity = Setting(key: "controlBarOpacity", defaultValue: 0.8)
    /// Seconds the controls stay up after the pointer stops moving during playback.
    static let controlsAutoHideDelay = Setting(key: "controlsAutoHideDelay", defaultValue: 1.5)
    /// Draw the watch heatmap above the seek bar: which parts of the file were played most.
    static let showWatchHeatmap = Setting(key: "showWatchHeatmap", defaultValue: true)
    /// Seconds an OSD message stays on screen.
    static let osdDuration = Setting(key: "osdDuration", defaultValue: 1.5)
}
