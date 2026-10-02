#if canImport(AppKit)
import AppKit

/// Plays a haptic each time the force level changes.
///
/// Uses the trackpad's actuator directly (`MultitouchActuator`) when it's
/// available, since that fires at every level and has six waveforms. Otherwise
/// it falls back to `NSHapticFeedbackManager`, which only has three patterns
/// and may skip pulses while a click or force click is in progress.
@MainActor
public final class LevelHaptics {
    public enum Engine: String, CaseIterable, Identifiable {
        case trackpadActuator
        case appKit

        public var id: String { rawValue }
    }

    public var isEnabled = true
    public var playsOnRelease = false
    public var profile = LevelHapticProfile.escalating

    /// The engine to use. If the trackpad actuator isn't available, AppKit is used.
    public var preferredEngine: Engine = .trackpadActuator

    /// `true` if the trackpad actuator could be opened on this Mac.
    public var isActuatorAvailable: Bool { actuator != nil }

    /// The engine pulses actually go through.
    public var activeEngine: Engine {
        preferredEngine == .trackpadActuator && actuator != nil ? .trackpadActuator : .appKit
    }

    private lazy var actuator: MultitouchActuator? = MultitouchActuator()
    private let performer: NSHapticFeedbackPerformer
    private var pending: Task<Void, Never>?

    public init(performer: NSHapticFeedbackPerformer? = nil) {
        self.performer = performer ?? NSHapticFeedbackManager.defaultPerformer
    }

    /// Plays the profile's pulses for `reading` if its level changed.
    public func handle(_ reading: PressureReading, levelCount: Int) {
        guard isEnabled, reading.levelChanged, reading.level > 0 else { return }

        if reading.level > reading.previousLevel {
            play(profile.pulses(forLevel: reading.level, levelCount: levelCount))
        } else if playsOnRelease {
            play(profile.stepDown)
        }
    }

    /// Plays a sequence of waveforms, cancelling any sequence still playing so
    /// the newest level always wins.
    public func play(_ pulses: [HapticWaveform]) {
        pending?.cancel()
        pending = nil
        guard let first = pulses.first else { return }
        fire(first)
        guard pulses.count > 1 else { return }

        let spacing = UInt64(profile.pulseSpacing * 1_000_000_000)
        pending = Task { @MainActor [weak self] in
            for pulse in pulses.dropFirst() {
                try? await Task.sleep(nanoseconds: spacing)
                guard !Task.isCancelled else { return }
                self?.fire(pulse)
            }
        }
    }

    /// Plays every level's haptic in turn so you can compare them.
    /// Keep a finger resting on the trackpad to feel them.
    public func previewAllLevels(levelCount: Int, interval: TimeInterval = 0.7, onLevel: (@MainActor (Int) -> Void)? = nil) {
        pending?.cancel()
        let gap = UInt64(interval * 1_000_000_000)
        pending = Task { @MainActor [weak self] in
            for level in 1...max(levelCount, 1) {
                guard let self = self, !Task.isCancelled else { return }
                onLevel?(level)
                self.playWithoutCancelling(self.profile.pulses(forLevel: level, levelCount: levelCount))
                try? await Task.sleep(nanoseconds: gap)
            }
            onLevel?(0)
        }
    }

    private func playWithoutCancelling(_ pulses: [HapticWaveform]) {
        let spacing = UInt64(profile.pulseSpacing * 1_000_000_000)
        for (i, pulse) in pulses.enumerated() {
            if i == 0 {
                fire(pulse)
            } else {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: spacing * UInt64(i))
                    self?.fire(pulse)
                }
            }
        }
    }

    private func fire(_ waveform: HapticWaveform) {
        if activeEngine == .trackpadActuator, let actuator = actuator, actuator.actuate(waveform) {
            return
        }
        performer.perform(waveform.appKitPattern, performanceTime: .now)
    }
}

extension HapticWaveform {
    /// Closest of AppKit's three patterns.
    var appKitPattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .weakClick, .lightTap: return .generic
        case .mediumTap, .strongClick: return .alignment
        case .strongTap, .buzz: return .levelChange
        }
    }
}
#endif
