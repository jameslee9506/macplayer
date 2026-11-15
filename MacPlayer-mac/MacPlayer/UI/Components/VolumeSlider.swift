import SwiftUI

/// Compact volume control with mute button and always-visible slider.
struct VolumeSlider: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Mute/unmute button
            Button(action: { isMuted.toggle() }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(PlayerControlButtonStyle())
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
            .accessibilityValue("Volume \(Int(volume * 100))%")

            // Volume slider — always visible
            GeometryReader { geometry in
                let width = geometry.size.width

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: max(0, width * CGFloat(isMuted ? 0 : volume)), height: 4)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if isMuted { isMuted = false }
                            volume = Float(max(0, min(value.location.x / width, 1.0)))
                        }
                )
            }
            .frame(width: 70, height: 20)
        }
    }

    private var volumeIcon: String {
        if isMuted || volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}
