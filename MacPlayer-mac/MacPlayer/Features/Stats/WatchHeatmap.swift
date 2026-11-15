import Foundation

/// How a media has been watched, ready to draw above the seek bar: a level for each point of
/// the timeline, higher where that part was played more.
///
/// A level is the number of times a part was played, relative to the part played most. The
/// scale never zooms in closer than `fullScalePlays`, so a media watched once through draws
/// a low band and only the parts gone back to rise above it.
struct WatchHeatmap: Equatable, Sendable {
    /// Plays that reach the top of the graph, until some part has had more.
    static let fullScalePlays = 3.0
    /// Most points a graph is drawn with.
    static let maxPointCount = 256
    /// A graph that stays below this level everywhere would not show, and is not made.
    static let faintestLevel = 0.02

    /// Levels in `0...1` at evenly spaced points: the first at the start of the media, the
    /// last at its end.
    let levels: [Float]

    /// The graph of a watch-time series. `nil` when too little was watched to draw anything.
    init?(watchTime series: TimelineSeries, duration: Double) {
        guard duration.isFinite, duration > 0 else { return nil }
        let width = series.binWidth
        // Bins that start past the end of the media, left from a longer duration, are not drawn.
        let binsWithinDuration = (duration / width).rounded(.up)
        let count = binsWithinDuration < Double(series.bins.count) ? Int(binsWithinDuration) : series.bins.count
        guard count > 0 else { return nil }

        // Seconds watched become times played: a bin watched for its whole width was played once.
        var plays = series.bins.prefix(count).map { Double($0) / width }

        // The last bin usually reaches past the end of the media, and only the part before
        // the end can be watched. When that part is a sliver, a frame more or less would
        // swing its count, so it is taken together with the bin before it.
        let tail = duration - Double(count - 1) * width
        if tail < width {
            let last = Double(series.bins[count - 1])
            if tail < width / 2, count > 1 {
                let merged = (Double(series.bins[count - 2]) + last) / (width + tail)
                plays[count - 2] = merged
                plays[count - 1] = merged
            } else {
                plays[count - 1] = last / tail
            }
        }

        let smoothed = Self.smoothed(plays)
        let peak = smoothed.max() ?? 0
        let scale = max(peak, Self.fullScalePlays)
        guard peak / scale >= Self.faintestLevel else { return nil }

        let pointCount = max(2, min(count, Self.maxPointCount))
        levels = (0..<pointCount).map { point in
            // Where the point falls among the bins, counted from the centre of the first one.
            let time = duration * Double(point) / Double(pointCount - 1)
            let position = min(max(time / width - 0.5, 0), Double(count - 1))
            let lower = Int(position)
            let upper = min(lower + 1, count - 1)
            let value = smoothed[lower] + (smoothed[upper] - smoothed[lower]) * (position - Double(lower))
            return Float(min(value / scale, 1))
        }
    }

    /// Rounds the bin-to-bin steps off into a curve: a Gaussian blur about 0.6% of the
    /// timeline wide, and never narrower than one bin.
    private static func smoothed(_ values: [Double]) -> [Double] {
        let sigma = max(1, Double(values.count) / 160)
        let radius = Int((sigma * 3).rounded(.up))
        let weights = (0...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }

        return values.indices.map { index in
            // Near either end the kernel hangs over the edge; the weights that remain are
            // rescaled so the curve does not sag there.
            var sum = 0.0
            var weightSum = 0.0
            for offset in -radius...radius where values.indices.contains(index + offset) {
                sum += values[index + offset] * weights[abs(offset)]
                weightSum += weights[abs(offset)]
            }
            return sum / weightSum
        }
    }
}
