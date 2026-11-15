import SwiftUI

/// On-Screen Display overlay for transient status messages (volume, seek, rate, etc.)
/// iOS-inspired design with material blur capsule and compact layout.
struct OSDView: View {
    let message: OSDMessage

    var body: some View {
        Group {
            if case .volume(let v) = message {
                volumeContent(value: v)
            } else if case .seek(let t, let d) = message {
                seekContent(current: t, duration: d)
            } else {
                defaultContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .preferredColorScheme(.dark)
    }

    // MARK: - Volume: icon + bar + percentage

    private func volumeContent(value: Float) -> some View {
        HStack(spacing: 8) {
            Image(systemName: message.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.white)
                    .frame(width: max(2, 80 * CGFloat(value)))
            }
            .frame(width: 80, height: 4)
            .clipShape(Capsule())
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Seek: clean time display, no icon

    private func seekContent(current: Double, duration: Double) -> some View {
        let progress = duration > 0 ? current / duration : 0
        return VStack(spacing: 6) {
            HStack(spacing: 3) {
                Text(formatTime(current))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("/")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                Text(formatTime(duration))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.white.opacity(0.7))
                    .frame(width: max(2, 120 * progress))
            }
            .frame(width: 120, height: 3)
            .clipShape(Capsule())
        }
    }

    // MARK: - Default: icon + text

    private var defaultContent: some View {
        HStack(spacing: 8) {
            Image(systemName: message.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// Manages OSD display lifecycle with auto-dismiss.
@MainActor
@Observable
final class OSDManager {
    var currentMessage: OSDMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: OSDMessage, duration: TimeInterval = 1.5) {
        dismissTask?.cancel()
        currentMessage = message

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                currentMessage = nil
            }
        }
    }
}
