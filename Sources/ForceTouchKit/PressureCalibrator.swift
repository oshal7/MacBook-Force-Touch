import Foundation

/// Measures how hard a user can comfortably press so `calibrationMax` can be
/// set to match.
///
/// Record raw samples while the user presses as hard as is comfortable, then
/// apply `recommendedCalibrationMax` to the quantizer configuration.
public struct PressureCalibrator {
    public private(set) var peak: Double = 0
    public private(set) var sampleCount = 0

    /// Fraction of the measured peak that counts as full force, so the top
    /// level is reachable without pressing at the absolute limit every time.
    public var headroom: Double
    /// Floor for the result, so a very light calibration press doesn't make
    /// the tracker hypersensitive.
    public var minimumMax: Double

    public init(headroom: Double = 0.9, minimumMax: Double = 0.2) {
        self.headroom = headroom
        self.minimumMax = minimumMax
    }

    public mutating func record(_ raw: Double) {
        guard raw.isFinite else { return }
        peak = max(peak, raw)
        sampleCount += 1
    }

    public mutating func reset() {
        peak = 0
        sampleCount = 0
    }

    /// `nil` until at least one non-zero sample has been recorded.
    public var recommendedCalibrationMax: Double? {
        guard sampleCount > 0, peak > 0 else { return nil }
        return min(max(peak * headroom, minimumMax), 1)
    }
}
