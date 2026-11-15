import SwiftUI

/// Draws a `WatchHeatmap` as an area graph: the taller, the more that part of the media was
/// watched. It spans the seek bar, so a point of the graph sits above its place on the bar.
struct WatchHeatmapView: View {
    let heatmap: WatchHeatmap

    var body: some View {
        ZStack {
            HeatmapShape(levels: heatmap.levels, isClosed: true)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.42), .white.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            HeatmapShape(levels: heatmap.levels, isClosed: false)
                .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                // Where nothing was watched the line would run along the seek bar's edge.
                .mask { Rectangle().padding(.top, -1).padding(.bottom, 1) }
        }
        // Keeps the graph readable over a bright picture.
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
        .accessibilityHidden(true)
    }
}

/// Outline of the graph: a curve through the levels, closed along the bottom for the fill.
private struct HeatmapShape: Shape {
    let levels: [Float]
    let isClosed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard levels.count > 1 else { return path }

        let spacing = rect.width / CGFloat(levels.count - 1)
        func point(_ index: Int) -> CGPoint {
            CGPoint(
                x: rect.minX + spacing * CGFloat(index),
                y: rect.maxY - rect.height * CGFloat(levels[index])
            )
        }

        // Curves run between the midpoints of neighbouring points, bent towards the point in
        // between. That rounds every corner without ever rising above a level.
        path.move(to: point(0))
        for index in 1..<levels.count - 1 {
            let current = point(index)
            let next = point(index + 1)
            path.addQuadCurve(
                to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2),
                control: current
            )
        }
        path.addLine(to: point(levels.count - 1))

        if isClosed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
