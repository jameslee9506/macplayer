import AppKit

/// Manages keyboard shortcuts for player controls.
/// Uses a configurable [KeyBinding] array instead of hardcoded switch statements.
/// Key presses are supplied by the player window (see `PlayerWindow`); this class only maps them to actions.
@MainActor
final class KeyBindingManager {
    private weak var engine: PlaybackEngine?
    private var lastSeekTime: CFAbsoluteTime = 0
    private let seekRepeatInterval: CFAbsoluteTime = 0.1  // 100ms throttle for key repeat

    private(set) var bindings: [KeyBinding]

    private let storageKey = "MacPlayer.KeyBindings"

    init() {
        // Load saved bindings or use defaults
        if let data = UserDefaults.standard.data(forKey: "MacPlayer.KeyBindings"),
           let saved = try? JSONDecoder().decode([KeyBinding].self, from: data) {
            // Merge any new default bindings not present in saved set
            let savedActions = Set(saved.map(\.action))
            let missing = KeyBinding.defaultBindings().filter { !savedActions.contains($0.action) }
            self.bindings = saved + missing
        } else {
            self.bindings = KeyBinding.defaultBindings()
        }
    }

    func setup(engine: PlaybackEngine) {
        self.engine = engine
    }

    // MARK: - Binding Management

    func updateBinding(for action: PlayerAction, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if let index = bindings.firstIndex(where: { $0.action == action }) {
            bindings[index] = KeyBinding(action: action, keyCode: keyCode, modifiers: modifiers.rawValue)
        }
        saveBindings()
    }

    func resetToDefaults() {
        bindings = KeyBinding.defaultBindings()
        saveBindings()
    }

    private func saveBindings() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Event Handling

    /// Runs the action bound to a key press in the player window.
    /// Returns `true` when the event was consumed.
    func handle(_ event: NSEvent) -> Bool {
        guard let engine else { return false }

        // Strip .numericPad and .function — arrow keys and function keys set these automatically
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])

        // Find matching binding
        guard let binding = bindings.first(where: {
            $0.keyCode == event.keyCode && $0.modifierFlags == modifiers
        }) else {
            return false
        }

        // Throttle key repeats for seek actions — limit to ~10 seeks/sec like IINA
        if event.isARepeat, binding.action.isSeeking {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastSeekTime < seekRepeatInterval {
                return true  // Too soon, skip this repeat
            }
            lastSeekTime = now
        }

        executeAction(binding.action, engine: engine, window: event.window)
        return true
    }

    private func executeAction(_ action: PlayerAction, engine: PlaybackEngine, window: NSWindow?) {
        switch action {
        case .togglePlayPause:
            engine.togglePlayPause()

        case .seekForwardSmall:
            let step = UserDefaults.standard.double(forKey: "seekSmallStep")
            Task { await engine.seekRelative(by: step > 0 ? step : 5) }

        case .seekBackwardSmall:
            let step = UserDefaults.standard.double(forKey: "seekSmallStep")
            Task { await engine.seekRelative(by: -(step > 0 ? step : 5)) }

        case .seekForwardLarge:
            let step = UserDefaults.standard.double(forKey: "seekLargeStep")
            Task { await engine.seekRelative(by: step > 0 ? step : 30) }

        case .seekBackwardLarge:
            let step = UserDefaults.standard.double(forKey: "seekLargeStep")
            Task { await engine.seekRelative(by: -(step > 0 ? step : 30)) }

        case .volumeUp:
            engine.adjustVolume(by: 0.05)

        case .volumeDown:
            engine.adjustVolume(by: -0.05)

        case .toggleMute:
            engine.toggleMute()

        case .cyclePlaybackRate:
            engine.cyclePlaybackRate()

        case .addBookmark:
            engine.addBookmark()

        case .nextBookmark:
            Task { await engine.seekToNextBookmark() }

        case .previousBookmark:
            Task { await engine.seekToPreviousBookmark() }

        case .playNext:
            Task { await engine.playNext() }

        case .playPrevious:
            Task { await engine.playPrevious() }

        case .takeScreenshot:
            engine.takeScreenshot()

        case .frameStepForward:
            engine.stepForward()

        case .frameStepBackward:
            engine.stepBackward()

        case .setLoopA:
            engine.setLoopPointA()

        case .setLoopB:
            engine.setLoopPointB()

        case .clearLoop:
            engine.clearABLoop()

        case .toggleFullScreen:
            window?.toggleFullScreen(nil)

        case .rotateVideo:
            engine.rotateVideo()

        case .audioDelayIncrease:
            engine.adjustAudioDelay(by: 0.1)

        case .audioDelayDecrease:
            engine.adjustAudioDelay(by: -0.1)

        case .audioDelayReset:
            engine.resetAudioDelay()

        case .togglePiP:
            engine.togglePiP()

        case .cycleSubtitleTrack:
            engine.cycleSubtitleTrack()

        case .cycleAudioTrack:
            engine.cycleAudioTrack()

        case .toggleHighlights:
            engine.toggleHighlights()

        case .markHighlightStart:
            engine.markHighlightStart()

        case .markHighlightEnd:
            engine.markHighlightEnd()
        }
    }
}
