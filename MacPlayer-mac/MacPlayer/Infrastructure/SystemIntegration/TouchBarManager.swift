import AppKit

/// Manages Touch Bar integration with play/pause, seek slider, and time display.
@MainActor
final class TouchBarManager: NSObject {
    private weak var engine: PlaybackEngine?
    private var syncTimer: Timer?

    private var playPauseButton: NSButton?
    private var seekSlider: NSSlider?
    private var timeLabel: NSTextField?
    private var touchBar: NSTouchBar?

    init(engine: PlaybackEngine) {
        self.engine = engine
        super.init()
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [
            .touchBarPlayPause,
            .touchBarSeekSlider,
            .touchBarTimeDisplay
        ]
        touchBar = bar
        startSyncTimer()
        return bar
    }

    func teardown() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncState()
            }
        }
    }

    private func syncState() {
        guard let engine else { return }

        // Update play/pause button
        let imageName = engine.state == .playing ? NSImage.touchBarPauseTemplateName : NSImage.touchBarPlayTemplateName
        playPauseButton?.image = NSImage(named: imageName)

        // Update seek slider
        if engine.duration > 0 {
            seekSlider?.doubleValue = engine.currentTime / engine.duration
        }

        // Update time label
        timeLabel?.stringValue = "\(formatTime(engine.currentTime)) / \(formatTime(engine.duration))"
    }

    @objc private func playPauseTapped() {
        engine?.togglePlayPause()
    }

    @objc private func seekSliderChanged(_ sender: NSSlider) {
        guard let engine else { return }
        let time = sender.doubleValue * engine.duration
        Task { await engine.seek(to: time) }
    }
}

// MARK: - Touch Bar Item Identifiers

extension NSTouchBarItem.Identifier {
    static let touchBarPlayPause = NSTouchBarItem.Identifier("io.github.jameslee9506.macplayer.touchbar.playpause")
    static let touchBarSeekSlider = NSTouchBarItem.Identifier("io.github.jameslee9506.macplayer.touchbar.seek")
    static let touchBarTimeDisplay = NSTouchBarItem.Identifier("io.github.jameslee9506.macplayer.touchbar.time")
}

// MARK: - NSTouchBarDelegate

extension TouchBarManager: NSTouchBarDelegate {
    nonisolated func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        MainActor.assumeIsolated {
            switch identifier {
            case .touchBarPlayPause:
                let item = NSCustomTouchBarItem(identifier: identifier)
                let button = NSButton(
                    image: NSImage(named: NSImage.touchBarPlayTemplateName)!,
                    target: self,
                    action: #selector(playPauseTapped)
                )
                playPauseButton = button
                item.view = button
                return item

            case .touchBarSeekSlider:
                let item = NSCustomTouchBarItem(identifier: identifier)
                let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(seekSliderChanged(_:)))
                slider.frame = NSRect(x: 0, y: 0, width: 300, height: 30)
                seekSlider = slider
                item.view = slider
                return item

            case .touchBarTimeDisplay:
                let item = NSCustomTouchBarItem(identifier: identifier)
                let label = NSTextField(labelWithString: "0:00 / 0:00")
                label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                label.alignment = .center
                timeLabel = label
                item.view = label
                return item

            default:
                return nil
            }
        }
    }
}
