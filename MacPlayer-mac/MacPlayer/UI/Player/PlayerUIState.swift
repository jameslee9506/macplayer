import Foundation
import Observation

/// Presentation state shared by the AppKit window layer and the SwiftUI overlays.
///
/// `PlayerWindowController` owns the policy (auto-hide, clicks, shortcuts) and writes this state;
/// SwiftUI renders it and writes back only through its buttons.
@MainActor
@Observable
final class PlayerUIState {
    /// Whether the title strip and the control bar are visible.
    var showControls = true

    /// Selected sidebar tab; `nil` means the sidebar is closed.
    var sidebarTab: SidebarTab? = nil {
        didSet {
            if let sidebarTab { lastSidebarTab = sidebarTab }
            if (oldValue == nil) != (sidebarTab == nil) {
                onSidebarVisibilityChange?(sidebarTab != nil)
            }
        }
    }

    /// Most recently selected tab. Keeps the panel's content on screen while it slides out.
    private(set) var lastSidebarTab: SidebarTab = .playlist

    /// Whether the keyboard shortcut guide covers the window.
    var showShortcutGuide = false {
        didSet {
            if oldValue != showShortcutGuide {
                onShortcutGuideVisibilityChange?(showShortcutGuide)
            }
        }
    }

    /// Called when the sidebar opens or closes, so AppKit can resize the video region.
    @ObservationIgnored var onSidebarVisibilityChange: ((Bool) -> Void)?

    /// Called when the shortcut guide is shown or dismissed.
    @ObservationIgnored var onShortcutGuideVisibilityChange: ((Bool) -> Void)?
}
