import Foundation

/// Trackpad haptic waveforms. The raw values are MultitouchSupport actuation
/// IDs. IDs beyond these may or may not work depending on firmware.
public enum HapticWaveform: Int32, CaseIterable, Codable {
    case weakClick = 1
    case strongClick = 2
    case buzz = 3
    case lightTap = 4
    case mediumTap = 5
    case strongTap = 6
}

/// What to play when entering each level: one or more waveforms in sequence.
public struct LevelHapticProfile: Equatable {
    /// `pulses[i]` plays on entering level `i + 1`.
    public var pulses: [[HapticWaveform]]
    /// Gap between pulses within one level.
    public var pulseSpacing: TimeInterval
    /// Played on stepping down, when that's enabled.
    public var stepDown: [HapticWaveform]

    public init(pulses: [[HapticWaveform]], pulseSpacing: TimeInterval = 0.06, stepDown: [HapticWaveform] = [.lightTap]) {
        self.pulses = pulses
        self.pulseSpacing = pulseSpacing
        self.stepDown = stepDown
    }

    /// Gets stronger level by level, then adds pulses: single taps for levels
    /// 1–5, double pulses for 6–8, a triple at 9 and a buzz at 10.
    public static let escalating = LevelHapticProfile(pulses: [
        [.lightTap],
        [.weakClick],
        [.mediumTap],
        [.strongTap],
        [.strongClick],
        [.mediumTap, .mediumTap],
        [.strongTap, .strongTap],
        [.strongClick, .strongClick],
        [.strongTap, .strongTap, .strongTap],
        [.buzz],
    ])

    /// The same strong tap at every level.
    public static let uniform = LevelHapticProfile(pulses: Array(repeating: [.strongTap], count: 10))

    /// The waveforms for `level` out of `levelCount`. If the profile has a
    /// different number of entries than there are levels, levels are spread
    /// evenly across it.
    public func pulses(forLevel level: Int, levelCount: Int) -> [HapticWaveform] {
        guard level > 0, !pulses.isEmpty else { return [] }
        let index: Int
        if levelCount <= 1 || pulses.count == levelCount {
            index = level - 1
        } else {
            let t = Double(level - 1) / Double(levelCount - 1)
            index = Int((t * Double(pulses.count - 1)).rounded())
        }
        return pulses[min(max(index, 0), pulses.count - 1)]
    }
}
