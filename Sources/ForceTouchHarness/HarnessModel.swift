import AppKit
import ForceTouchKit
import SwiftUI

@MainActor
final class HarnessModel: ObservableObject {
    @Published private(set) var reading = PressureReading.idle
    @Published private(set) var latencyMs: Double = 0
    @Published private(set) var peakLevel = 0

    @Published var configuration = QuantizerConfiguration.default
    @Published var inputMapping = ForceInputMapping.stageCombined
    @Published var hapticsEnabled = true
    @Published var hapticsOnRelease = false

    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationSecondsLeft = 0

    private var calibrator = PressureCalibrator()
    private var calibrationTimer: Timer?
    static let calibrationDuration = 4

    func ingest(_ reading: PressureReading) {
        self.reading = reading
        peakLevel = max(peakLevel, reading.level)
        if reading.timestamp > 0 {
            // Time from the hardware event to this handler. SwiftUI renders on
            // the next display refresh after this.
            let ms = (ProcessInfo.processInfo.systemUptime - reading.timestamp) * 1000
            latencyMs = latencyMs == 0 ? ms : latencyMs * 0.9 + ms * 0.1
        }
        if isCalibrating {
            calibrator.record(reading.raw)
        }
    }

    func resetPeak() {
        peakLevel = 0
    }

    func startCalibration() {
        calibrator.reset()
        isCalibrating = true
        calibrationSecondsLeft = Self.calibrationDuration
        calibrationTimer?.invalidate()
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickCalibration() }
        }
    }

    func resetCalibration() {
        configuration.calibrationMax = 1
    }

    private func tickCalibration() {
        calibrationSecondsLeft -= 1
        guard calibrationSecondsLeft <= 0 else { return }
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        isCalibrating = false
        if let max = calibrator.recommendedCalibrationMax {
            configuration.calibrationMax = max
        }
    }
}
