#if canImport(AppKit)
import AppKit

/// One haptic the engine tried to play, for diagnostics.
public struct HapticEvent: Equatable {
    public enum Kind: String {
        /// The pulse played on entering a level.
        case detent
        /// A repeating pulse while a level is held.
        case rumble
        case preview
    }

    public var kind: Kind
    public var level: Int
    public var waveform: HapticWaveform
    public var engine: LevelHaptics.Engine
    /// `false` if the trackpad actuator rejected the pulse (AppKit was used instead).
    public var actuatorAccepted: Bool
}

/// Haptic feedback for force levels.
///
/// Two layers:
/// - **Detents**: a distinct pulse pattern each time the level goes up
///   (`profile`).
/// - **Rumble**: while a level is held, a repeating pulse that gets faster and
///   stronger the deeper the level, so a long hold keeps feeling deeper
///   instead of going quiet between level changes.
///
/// Uses the trackpad's actuator directly (`MultitouchActuator`) when it's
/// available, otherwise `NSHapticFeedbackManager`.
@MainActor
public final class LevelHaptics {
    public enum Engine: String, CaseIterable, Identifiable {
        case trackpadActuator
        case appKit

        public var id: String { rawValue }
    }

    public var isEnabled = true {
        didSet { if !isEnabled { stopRumble() } }
    }
    public var playsOnRelease = false
    public var profile = LevelHapticProfile.escalating

    /// Repeating pulse while a level is held.
    public var rumbleEnabled = true {
        didSet { if !rumbleEnabled { stopRumble() } }
    }
    /// Gap between rumble pulses at level 1.
    public var rumbleSlowestInterval: TimeInterval = 0.36
    /// Gap between rumble pulses at the top level.
    public var rumbleFastestInterval: TimeInterval = 0.07

    /// The engine to use. If the trackpad actuator isn't available, AppKit is used.
    public var preferredEngine: Engine = .trackpadActuator

    /// Called for every pulse fired.
    public var onEvent: (@MainActor (HapticEvent) -> Void)?

    /// `true` if the trackpad actuator could be opened on this Mac.
    public var isActuatorAvailable: Bool { actuator != nil }

    /// The engine pulses actually go through.
    public var activeEngine: Engine {
        preferredEngine == .trackpadActuator && actuator != nil ? .trackpadActuator : .appKit
    }

    private lazy var actuator: MultitouchActuator? = MultitouchActuator()
    private let performer: NSHapticFeedbackPerformer
    private var pending: Task<Void, Never>?
    private var rumbleTask: Task<Void, Never>?
    private var rumbleID = 0
    private var heldLevel = 0
    private var heldLevelCount = 10
    private var lastDetentTime: TimeInterval = 0

    public init(performer: NSHapticFeedbackPerformer? = nil) {
        self.performer = performer ?? NSHapticFeedbackManager.defaultPerformer
    }

    /// Updates haptics for a new reading: plays a detent when the level rises
    /// and keeps the rumble in step with the held level.
    public func handle(_ reading: PressureReading, levelCount: Int) {
        heldLevel = reading.level
        heldLevelCount = levelCount
        guard isEnabled else { return }

        if reading.level == 0 {
            stopRumble()
            return
        }

        if reading.levelChanged {
            if reading.level > reading.previousLevel {
                play(profile.pulses(forLevel: reading.level, levelCount: levelCount), kind: .detent, level: reading.level)
            } else if playsOnRelease {
                play(profile.stepDown, kind: .detent, level: reading.level)
            }
        }

        if rumbleEnabled && rumbleTask == nil {
            startRumble()
        }
    }

    /// Stops everything, e.g. when the finger lifts.
    public func stop() {
        heldLevel = 0
        pending?.cancel()
        pending = nil
        stopRumble()
    }

    /// Plays a sequence of waveforms, cancelling any detent still playing so
    /// the newest level always wins.
    public func play(_ pulses: [HapticWaveform], kind: HapticEvent.Kind = .detent, level: Int = 0) {
        pending?.cancel()
        pending = nil
        guard let first = pulses.first else { return }
        lastDetentTime = ProcessInfo.processInfo.systemUptime + profile.pulseSpacing * Double(pulses.count - 1)
        fire(first, kind: kind, level: level)
        guard pulses.count > 1 else { return }

        let spacing = UInt64(profile.pulseSpacing * 1_000_000_000)
        pending = Task { @MainActor [weak self] in
            for pulse in pulses.dropFirst() {
                try? await Task.sleep(nanoseconds: spacing)
                guard !Task.isCancelled else { return }
                self?.fire(pulse, kind: kind, level: level)
            }
        }
    }

    /// Plays every level's detent in turn so you can compare them.
    /// Keep a finger resting on the trackpad to feel them.
    public func previewAllLevels(levelCount: Int, interval: TimeInterval = 0.7, onLevel: (@MainActor (Int) -> Void)? = nil) {
        stop()
        let gap = UInt64(interval * 1_000_000_000)
        let spacing = UInt64(profile.pulseSpacing * 1_000_000_000)
        pending = Task { @MainActor [weak self] in
            for level in 1...max(levelCount, 1) {
                guard let self = self, !Task.isCancelled else { return }
                onLevel?(level)
                for (i, pulse) in self.profile.pulses(forLevel: level, levelCount: levelCount).enumerated() {
                    if i > 0 { try? await Task.sleep(nanoseconds: spacing) }
                    self.fire(pulse, kind: .preview, level: level)
                }
                try? await Task.sleep(nanoseconds: gap)
            }
            onLevel?(0)
        }
    }

    // MARK: - Rumble

    /// Gap between rumble pulses at `level`.
    public func rumbleInterval(level: Int, levelCount: Int) -> TimeInterval {
        let t = levelCount > 1 ? Double(min(max(level, 1), levelCount) - 1) / Double(levelCount - 1) : 1
        return rumbleSlowestInterval + (rumbleFastestInterval - rumbleSlowestInterval) * t
    }

    /// Rumble waveform at `level`: light, then medium, then strong taps.
    public func rumbleWaveform(level: Int, levelCount: Int) -> HapticWaveform {
        let t = levelCount > 1 ? Double(level - 1) / Double(levelCount - 1) : 1
        switch t {
        case ..<0.3: return .lightTap
        case ..<0.65: return .mediumTap
        default: return .strongTap
        }
    }

    private func startRumble() {
        rumbleID += 1
        let id = rumbleID
        rumbleTask = Task { @MainActor [weak self] in
            while let self = self, self.rumbleID == id, !Task.isCancelled, self.heldLevel > 0 {
                let interval = self.rumbleInterval(level: self.heldLevel, levelCount: self.heldLevelCount)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, self.heldLevel > 0, self.isEnabled, self.rumbleEnabled else { break }
                // Leave the detent for a new level room to be felt on its own.
                if ProcessInfo.processInfo.systemUptime - self.lastDetentTime < interval * 0.6 { continue }
                let level = self.heldLevel
                self.fire(self.rumbleWaveform(level: level, levelCount: self.heldLevelCount), kind: .rumble, level: level)
            }
            if self?.rumbleID == id {
                self?.rumbleTask = nil
            }
        }
    }

    private func stopRumble() {
        rumbleID += 1
        rumbleTask?.cancel()
        rumbleTask = nil
    }

    // MARK: - Output

    private func fire(_ waveform: HapticWaveform, kind: HapticEvent.Kind, level: Int) {
        var engine = Engine.appKit
        var accepted = true
        if activeEngine == .trackpadActuator, let actuator = actuator {
            if actuator.actuate(waveform) {
                engine = .trackpadActuator
            } else {
                accepted = false
            }
        }
        if engine == .appKit {
            performer.perform(waveform.appKitPattern, performanceTime: .now)
        }
        onEvent?(HapticEvent(kind: kind, level: level, waveform: waveform, engine: engine, actuatorAccepted: accepted))
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
