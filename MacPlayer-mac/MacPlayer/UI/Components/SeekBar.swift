import SwiftUI

/// Custom seek bar with drag-to-seek, click-to-seek, A-B loop markers, the watch heatmap, and
/// thumbnail preview.
struct SeekBar: View {
    let progress: Double
    let duration: Double
    let onSeek: (Double) -> Void
    var onScrubBegan: (() -> Void)? = nil
    var onScrub: ((Double) -> Void)? = nil
    var loopA: Double? = nil
    var loopB: Double? = nil
    var bookmarkTimes: [Double] = []
    var highlightSegments: [(start: Double, end: Double)] = []
    var watchHeatmap: WatchHeatmap? = nil
    var thumbnailGenerator: ThumbnailGenerator? = nil

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isHovering = false
    @State private var hoverProgress: Double = 0

    private var displayProgress: Double {
        isDragging ? dragProgress : progress
    }

    /// The progress value to show preview for (drag takes priority over hover)
    private var previewProgress: Double {
        isDragging ? dragProgress : hoverProgress
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = isHovering || isDragging ? 8 : 4

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(.white.opacity(0.2))
                    .frame(height: height)

                // Progress fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(.white)
                    .frame(width: max(0, width * displayProgress), height: height)

                // A-B loop markers
                if let a = loopA, duration > 0 {
                    let aPos = a / duration
                    Rectangle()
                        .fill(.green)
                        .frame(width: 2, height: 16)
                        .offset(x: width * aPos - 1)
                }
                if let b = loopB, duration > 0 {
                    let bPos = b / duration
                    Rectangle()
                        .fill(.red)
                        .frame(width: 2, height: 16)
                        .offset(x: width * bPos - 1)
                }
                if let a = loopA, let b = loopB, duration > 0 {
                    let aPos = a / duration
                    let bPos = b / duration
                    Rectangle()
                        .fill(.blue.opacity(0.15))
                        .frame(width: width * (bPos - aPos), height: height)
                        .offset(x: width * aPos)
                }

                // Highlight segments
                if duration > 0 {
                    ForEach(Array(highlightSegments.enumerated()), id: \.offset) { _, seg in
                        let startPos = seg.start / duration
                        let endPos = seg.end / duration
                        Rectangle()
                            .fill(.yellow.opacity(0.2))
                            .frame(width: max(1, width * (endPos - startPos)), height: height)
                            .offset(x: width * startPos)
                    }
                }

                // Bookmark markers
                if duration > 0 {
                    ForEach(Array(bookmarkTimes.enumerated()), id: \.offset) { _, time in
                        let pos = time / duration
                        Diamond()
                            .fill(.orange)
                            .frame(width: 7, height: 9)
                            .offset(x: width * pos - 3.5, y: -6)
                    }
                }

                // Hover indicator
                if isHovering && !isDragging {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .frame(width: 12, height: 12)
                        .offset(x: width * hoverProgress - 6)
                }

                // Drag knob
                if isDragging {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .frame(width: 14, height: 14)
                        .offset(x: width * dragProgress - 7)
                }
            }
            .frame(height: 20)
            .background(alignment: .top) {
                // Watch heatmap — stands on the track, behind the markers, and rises with it on hover
                if let watchHeatmap {
                    let isActive = isHovering || isDragging
                    let graphHeight: CGFloat = isActive ? 28 : 18
                    WatchHeatmapView(heatmap: watchHeatmap)
                        .frame(height: graphHeight)
                        .opacity(isActive ? 1 : 0.75)
                        // `10 - height / 2` is the top edge of the track, centred in the bar's 20 points.
                        .offset(y: 10 - height / 2 - graphHeight)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHovering = true
                    hoverProgress = max(0, min(location.x / width, 1.0))
                case .ended:
                    isHovering = false
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrubBegan?()
                        }
                        dragProgress = max(0, min(value.location.x / width, 1.0))
                        onScrub?(dragProgress * duration)
                    }
                    .onEnded { value in
                        let finalProgress = max(0, min(value.location.x / width, 1.0))
                        hoverProgress = finalProgress
                        isDragging = false
                        onSeek(finalProgress * duration)
                    }
            )
            .overlay(alignment: .topLeading) {
                // Thumbnail preview — visible during hover OR drag
                if (isHovering || isDragging), let gen = thumbnailGenerator, duration > 0 {
                    let previewTime = previewProgress * duration
                    let previewWidth: CGFloat = 240
                    let clampedX = min(max(width * previewProgress, previewWidth / 2), width - previewWidth / 2)
                    let preview = ThumbnailPreview(
                        image: gen.thumbnail(at: previewTime),
                        time: previewTime,
                        xPosition: clampedX
                    )
                    preview
                        .offset(x: clampedX - previewWidth / 2, y: -205)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .accessibilityLabel("Seek bar")
        .accessibilityValue("\(formatTime(displayProgress * duration)) of \(formatTime(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onSeek(min(displayProgress * duration + 5, duration))
            case .decrement:
                onSeek(max(displayProgress * duration - 5, 0))
            @unknown default:
                break
            }
        }
    }
}

/// Diamond shape for bookmark markers on the seek bar.
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: cy))
        path.addLine(to: CGPoint(x: cx, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: cy))
        path.closeSubpath()
        return path
    }
}
