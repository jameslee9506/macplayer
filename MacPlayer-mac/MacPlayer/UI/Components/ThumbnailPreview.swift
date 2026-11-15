import SwiftUI

/// Floating thumbnail preview shown when hovering over the seek bar.
/// Uses crossfade transition to avoid flickering between thumbnails.
struct ThumbnailPreview: View {
    let image: NSImage?
    let time: Double
    let xPosition: CGFloat

    private let previewWidth: CGFloat = 240
    private let minHeight: CGFloat = 100
    private let maxHeight: CGFloat = 180

    /// Calculate height from image aspect ratio, clamped to [100, 180]
    private var previewHeight: CGFloat {
        guard let image, image.size.width > 0 else { return 135 }
        let ratio = image.size.width / image.size.height
        return min(maxHeight, max(minHeight, previewWidth / ratio))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Placeholder — only visible before first thumbnail loads
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.5))
                    .frame(width: previewWidth, height: 135)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: previewWidth, height: previewHeight)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .animation(.easeOut(duration: 0.12), value: image)

            Text(formatTime(time))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.7), in: Capsule())
        }
    }
}
