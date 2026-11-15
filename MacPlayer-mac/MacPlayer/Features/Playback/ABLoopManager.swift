import Foundation

/// Manages A-B loop points for repeated playback of a segment.
@MainActor
@Observable
final class ABLoopManager {
    var pointA: Double?
    var pointB: Double?

    var isActive: Bool {
        pointA != nil && pointB != nil
    }

    /// Set point A to the current time
    func setPointA(_ time: Double) {
        pointA = time
        // Clear B if it's before A
        if let b = pointB, b <= time {
            pointB = nil
        }
    }

    /// Set point B to the current time
    func setPointB(_ time: Double) {
        guard let a = pointA, time > a else { return }
        pointB = time
    }

    /// Clear both loop points
    func clearLoop() {
        pointA = nil
        pointB = nil
    }

    /// Check if current playback time has reached point B and should loop back to A.
    /// Returns the time to seek to (point A) if looping should occur, nil otherwise.
    func shouldLoop(currentTime: Double) -> Double? {
        guard let a = pointA, let b = pointB else { return nil }
        if currentTime >= b {
            return a
        }
        return nil
    }
}
