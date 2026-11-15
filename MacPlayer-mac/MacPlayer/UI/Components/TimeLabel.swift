import SwiftUI

/// Formatted time display showing current time and duration.
struct TimeLabel: View {
    let currentTime: Double
    let duration: Double

    var body: some View {
        Text("\(formatTime(currentTime)) / \(formatTime(duration))")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
    }
}

/// Format seconds into HH:MM:SS or MM:SS string.
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && !seconds.isNaN else { return "00:00" }

    let totalSeconds = Int(max(0, seconds))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%02d:%02d", minutes, secs)
    }
}
