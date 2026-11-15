import Foundation
import AppKit

/// All possible player actions that can be bound to keyboard shortcuts.
enum PlayerAction: String, CaseIterable, Codable, Sendable {
    case togglePlayPause
    case seekForwardSmall
    case seekBackwardSmall
    case seekForwardLarge
    case seekBackwardLarge
    case volumeUp
    case volumeDown
    case toggleMute
    case cyclePlaybackRate
    case addBookmark
    case playNext
    case playPrevious
    case takeScreenshot
    case frameStepForward
    case frameStepBackward
    case setLoopA
    case setLoopB
    case clearLoop
    case toggleFullScreen
    case rotateVideo
    case nextBookmark
    case previousBookmark
    case audioDelayIncrease
    case audioDelayDecrease
    case audioDelayReset
    case togglePiP
    case cycleSubtitleTrack
    case cycleAudioTrack
    case toggleHighlights
    case markHighlightStart
    case markHighlightEnd

    /// Whether this action is a seek operation (subject to key-repeat throttling)
    var isSeeking: Bool {
        switch self {
        case .seekForwardSmall, .seekBackwardSmall, .seekForwardLarge, .seekBackwardLarge:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .togglePlayPause: return "Play / Pause"
        case .seekForwardSmall: return "Seek Forward"
        case .seekBackwardSmall: return "Seek Backward"
        case .seekForwardLarge: return "Seek Forward (Large)"
        case .seekBackwardLarge: return "Seek Backward (Large)"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .toggleMute: return "Toggle Mute"
        case .cyclePlaybackRate: return "Cycle Playback Rate"
        case .addBookmark: return "Add Bookmark"
        case .nextBookmark: return "Next Bookmark"
        case .previousBookmark: return "Previous Bookmark"
        case .playNext: return "Play Next"
        case .playPrevious: return "Play Previous"
        case .takeScreenshot: return "Take Screenshot"
        case .frameStepForward: return "Frame Step Forward"
        case .frameStepBackward: return "Frame Step Backward"
        case .setLoopA: return "Set Loop Point A"
        case .setLoopB: return "Set Loop Point B"
        case .clearLoop: return "Clear Loop"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .rotateVideo: return "Rotate Video"
        case .audioDelayIncrease: return "Audio Delay +0.1s"
        case .audioDelayDecrease: return "Audio Delay -0.1s"
        case .audioDelayReset: return "Reset Audio Delay"
        case .togglePiP: return "PiP 전환"
        case .cycleSubtitleTrack: return "Cycle Subtitle Track"
        case .cycleAudioTrack: return "Cycle Audio Track"
        case .toggleHighlights: return "Toggle Highlights"
        case .markHighlightStart: return "Mark Highlight Start"
        case .markHighlightEnd: return "Mark Highlight End"
        }
    }
}

/// A single key binding mapping a key combination to a player action.
struct KeyBinding: Identifiable, Codable, Sendable {
    var id: String { action.rawValue }
    let action: PlayerAction
    var keyCode: UInt16
    var modifiers: UInt  // Raw value of NSEvent.ModifierFlags

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).shortcutModifiers
    }

    /// Human-readable description of the key combination.
    var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("^") }
        if flags.contains(.option) { parts.append("\u{2325}") }
        if flags.contains(.shift) { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    static func defaultBindings() -> [KeyBinding] {
        [
            KeyBinding(action: .togglePlayPause, keyCode: 49, modifiers: 0),       // Space
            KeyBinding(action: .seekBackwardSmall, keyCode: 123, modifiers: 0),     // Left
            KeyBinding(action: .seekForwardSmall, keyCode: 124, modifiers: 0),      // Right
            KeyBinding(action: .seekBackwardLarge, keyCode: 123, modifiers: NSEvent.ModifierFlags.shift.rawValue), // Shift+Left
            KeyBinding(action: .seekForwardLarge, keyCode: 124, modifiers: NSEvent.ModifierFlags.shift.rawValue),  // Shift+Right
            KeyBinding(action: .volumeUp, keyCode: 126, modifiers: 0),              // Up
            KeyBinding(action: .volumeDown, keyCode: 125, modifiers: 0),            // Down
            KeyBinding(action: .toggleMute, keyCode: 46, modifiers: 0),             // M
            KeyBinding(action: .cyclePlaybackRate, keyCode: 15, modifiers: 0),      // R
            KeyBinding(action: .addBookmark, keyCode: 11, modifiers: 0),            // B
            KeyBinding(action: .nextBookmark, keyCode: 11, modifiers: NSEvent.ModifierFlags.shift.rawValue),     // Shift+B
            KeyBinding(action: .previousBookmark, keyCode: 11, modifiers: NSEvent.ModifierFlags.option.rawValue), // Option+B
            KeyBinding(action: .playNext, keyCode: 45, modifiers: 0),               // N
            KeyBinding(action: .playPrevious, keyCode: 35, modifiers: 0),           // P
            KeyBinding(action: .takeScreenshot, keyCode: 1, modifiers: 0),          // S
            KeyBinding(action: .frameStepForward, keyCode: 47, modifiers: 0),       // .
            KeyBinding(action: .frameStepBackward, keyCode: 43, modifiers: 0),      // ,
            KeyBinding(action: .setLoopA, keyCode: 33, modifiers: 0),               // [
            KeyBinding(action: .setLoopB, keyCode: 30, modifiers: 0),               // ]
            KeyBinding(action: .clearLoop, keyCode: 42, modifiers: 0),              // backslash
            KeyBinding(action: .toggleFullScreen, keyCode: 36, modifiers: 0),      // Enter/Return
            KeyBinding(action: .rotateVideo, keyCode: 40, modifiers: NSEvent.ModifierFlags.command.rawValue), // Cmd+K
            KeyBinding(action: .audioDelayIncrease, keyCode: 30, modifiers: NSEvent.ModifierFlags.control.rawValue),  // Ctrl+]
            KeyBinding(action: .audioDelayDecrease, keyCode: 33, modifiers: NSEvent.ModifierFlags.control.rawValue),  // Ctrl+[
            KeyBinding(action: .audioDelayReset, keyCode: 42, modifiers: NSEvent.ModifierFlags.control.rawValue),     // Ctrl+\
            KeyBinding(action: .togglePiP, keyCode: 35, modifiers: NSEvent.ModifierFlags.command.rawValue),             // Cmd+P
            KeyBinding(action: .cycleSubtitleTrack, keyCode: 38, modifiers: 0),            // J
            KeyBinding(action: .cycleAudioTrack, keyCode: 38, modifiers: NSEvent.ModifierFlags.shift.rawValue),  // Shift+J
            KeyBinding(action: .toggleHighlights, keyCode: 4, modifiers: 0),             // H
            KeyBinding(action: .markHighlightStart, keyCode: 4, modifiers: NSEvent.ModifierFlags.shift.rawValue),   // Shift+H
            KeyBinding(action: .markHighlightEnd, keyCode: 4, modifiers: NSEvent.ModifierFlags.option.rawValue),    // Option+H
        ]
    }
}

extension NSEvent.ModifierFlags {
    /// The modifiers that tell one shortcut from another: ⌘ ⌥ ⌃ ⇧.
    ///
    /// Everything else is dropped — Caps Lock, and the numeric-pad and function flags that
    /// arrow and function keys carry on their own. Compare shortcuts through this on both
    /// sides, or a binding stops matching whenever one of those flags happens to be set.
    var shortcutModifiers: NSEvent.ModifierFlags {
        intersection([.command, .option, .control, .shift])
    }
}

/// Convert a macOS keyCode to a human-readable string.
func keyCodeToString(_ keyCode: UInt16) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 48: return "Tab"
    case 49: return "Space"
    case 51: return "Delete"
    case 53: return "Esc"
    case 76: return "Enter"
    case 36: return "Return"
    case 123: return "\u{2190}" // Left arrow
    case 124: return "\u{2192}" // Right arrow
    case 125: return "\u{2193}" // Down arrow
    case 126: return "\u{2191}" // Up arrow
    default: return "Key\(keyCode)"
    }
}
