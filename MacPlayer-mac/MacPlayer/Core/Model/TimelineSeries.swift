import Foundation

/// A quantity added up along a media's timeline: the seconds each part was watched, for one.
///
/// The timeline is cut into bins of equal width, and each bin keeps a running total. Recording
/// adds to the bins a stretch of the timeline covers, so a series stays the same size however
/// many times the media is played.
///
/// Bins are as fine as `maxBinCount` allows: their width is `finestBinWidth`, doubled until the
/// whole duration fits. Because widths only ever double, the series of a media that got longer
/// (a download still in progress) is brought to its new width by adding bins up in pairs, which
/// keeps every total.
struct TimelineSeries: Equatable, Sendable {
    /// Most bins a series holds. Spread over a seek bar, that is a few pixels each.
    static let maxBinCount = 512
    /// Bin width, in seconds, of a media short enough to afford it.
    static let finestBinWidth = 0.25

    /// Seconds of the timeline one bin covers.
    private(set) var binWidth: Double
    /// Running total of each bin. Bin `i` covers `i * binWidth ..< (i + 1) * binWidth`.
    private(set) var bins: [Float]

    /// An empty series, not yet fitted to a media.
    init() {
        binWidth = Self.finestBinWidth
        bins = []
    }

    /// A series read back from storage. `nil` when the values cannot be one.
    init?(binWidth: Double, bins: [Float]) {
        guard binWidth.isFinite, binWidth > 0, bins.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        self.binWidth = binWidth
        self.bins = bins
        while self.bins.count > Self.maxBinCount { mergePairs() }
    }

    /// Whether nothing has been recorded.
    var isEmpty: Bool {
        !bins.contains { $0 > 0 }
    }

    /// Makes the series cover a timeline of `duration` seconds, keeping what is recorded.
    ///
    /// Bins are never dropped or split: a duration that turns out shorter leaves the series
    /// as it is.
    mutating func fit(duration: Double) {
        guard duration.isFinite, duration > 0 else { return }

        // With nothing recorded there is no width to keep: start as fine as this duration allows.
        if isEmpty { self = TimelineSeries() }

        while (duration / binWidth).rounded(.up) > Double(Self.maxBinCount) { mergePairs() }
        let count = Int((duration / binWidth).rounded(.up))
        if count > bins.count {
            bins.append(contentsOf: repeatElement(0, count: count - bins.count))
        }
    }

    /// Records the stretch of the timeline from `start` to `end`: every bin gains the seconds
    /// of the stretch that fall inside it. Anything outside the fitted timeline is left out.
    mutating func add(from start: Double, to end: Double) {
        let lower = max(start, 0)
        let upper = min(end, Double(bins.count) * binWidth)
        guard lower < upper else { return }

        var index = Int(lower / binWidth)
        var position = lower
        while index < bins.count, position < upper {
            let binEnd = min(Double(index + 1) * binWidth, upper)
            bins[index] += Float(max(binEnd - position, 0))
            position = binEnd
            index += 1
        }
    }

    /// Doubles the bin width: each pair of neighbours becomes one bin holding their sum.
    private mutating func mergePairs() {
        bins = stride(from: 0, to: bins.count, by: 2).map { index in
            bins[index] + (index + 1 < bins.count ? bins[index + 1] : 0)
        }
        binWidth *= 2
    }
}
