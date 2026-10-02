import AppKit
import ForceTouchKit
import SwiftUI

/// How clicks in the pad are configured.
enum PressureMode: String, CaseIterable, Identifiable {
    /// Normal click + force click. macOS plays its own haptic at both.
    case twoStage
    /// Click only, no force click, so only the level haptics play after the click.
    case singleStage

    var id: String { rawValue }

    var behavior: NSEvent.PressureBehavior {
        self == .twoStage ? .primaryDefault : .primaryClick
    }

    var mapping: ForceInputMapping {
        self == .twoStage ? .stageCombined : .raw
    }
}

enum HapticProfileChoice: String, CaseIterable, Identifiable {
    case escalating
    case uniform

    var id: String { rawValue }

    var profile: LevelHapticProfile {
        self == .escalating ? .escalating : .uniform
    }
}

@MainActor
final class HarnessModel: ObservableObject {
    @Published private(set) var reading = PressureReading.idle
    @Published private(set) var latencyMs: Double = 0
    @Published private(set) var peakLevel = 0
    /// Level being played by the haptic preview, or 0.
    @Published private(set) var previewLevel = 0

    @Published var configuration = QuantizerConfiguration.default
    @Published var pressureMode = PressureMode.twoStage
    @Published var hapticsEnabled = true { didSet { haptics.isEnabled = hapticsEnabled } }
    @Published var hapticsOnRelease = false { didSet { haptics.playsOnRelease = hapticsOnRelease } }
    @Published var hapticEngine = LevelHaptics.Engine.trackpadActuator {
        didSet { haptics.preferredEngine = hapticEngine }
    }
    @Published var hapticProfile = HapticProfileChoice.escalating {
        didSet { haptics.profile = hapticProfile.profile }
    }

    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationSecondsLeft = 0

    let haptics = LevelHaptics()

    private var calibrator = PressureCalibrator()
    private var calibrationTimer: Timer?
    static let calibrationDuration = 4

    var isActuatorAvailable: Bool { haptics.isActuatorAvailable }

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

    func previewHaptics() {
        haptics.previewAllLevels(levelCount: configuration.levelCount) { [weak self] level in
            self?.previewLevel = level
        }
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
