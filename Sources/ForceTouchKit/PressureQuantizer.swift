import Foundation

/// Tuning parameters for `PressureQuantizer`.
///
/// With the defaults, calibrated pressure is split into these bands:
///
/// | Level | Pressure            |
/// |-------|---------------------|
/// | 0     | `< 0.05` (deadzone) |
/// | 1     | `0.05 ..< 0.15`     |
/// | 2     | `0.15 ..< 0.25`     |
/// | ...   | ...                 |
/// | 9     | `0.85 ..< 0.95`     |
/// | 10    | `>= 0.95`           |
public struct QuantizerConfiguration: Equatable {
    /// Number of non-idle levels. Level 0 is always the idle deadzone.
    public var levelCount: Int
    /// Pressure below this value reports level 0.
    public var deadzone: Double
    /// Pressure at or above this value reports the top level.
    public var ceiling: Double
    /// Response curve applied after calibration.
    public var curve: PressureCurve
    /// How strongly a non-linear curve bends.
    public var curveStrength: Double
    /// How far pressure must fall below a band before the level drops.
    /// Stops the level flickering when a finger rests on a boundary.
    public var hysteresis: Double
    /// Raw pressure that counts as full force. Lower it for users who can't
    /// comfortably press all the way; `PressureCalibrator` can measure it.
    public var calibrationMax: Double

    public init(
        levelCount: Int = 10,
        deadzone: Double = 0.05,
        ceiling: Double = 0.95,
        curve: PressureCurve = .linear,
        curveStrength: Double = 3,
        hysteresis: Double = 0.02,
        calibrationMax: Double = 1
    ) {
        self.levelCount = levelCount
        self.deadzone = deadzone
        self.ceiling = ceiling
        self.curve = curve
        self.curveStrength = curveStrength
        self.hysteresis = hysteresis
        self.calibrationMax = calibrationMax
    }

    public static let `default` = QuantizerConfiguration()

    /// Width of each band between the deadzone and the ceiling.
    public var bandWidth: Double {
        (ceiling - deadzone) / Double(levelCount - 1)
    }

    /// The lowest normalized pressure that reports `level`.
    public func lowerBound(of level: Int) -> Double {
        if level <= 0 { return 0 }
        return deadzone + Double(min(level, levelCount) - 1) * bandWidth
    }

    /// Returns a copy with every value clamped into a usable range.
    public func sanitized() -> QuantizerConfiguration {
        var c = self
        c.levelCount = max(2, c.levelCount)
        c.deadzone = min(max(c.deadzone, 0), 0.5)
        c.ceiling = min(max(c.ceiling, c.deadzone + 0.01), 1)
        c.curveStrength = min(max(c.curveStrength, 0.1), 10)
        c.hysteresis = min(max(c.hysteresis, 0), c.bandWidth)
        c.calibrationMax = min(max(c.calibrationMax, 0.05), 1)
        return c
    }
}

/// One processed pressure sample.
public struct PressureReading: Equatable {
    /// Pressure as received, before calibration and curve.
    public var raw: Double
    /// Pressure after calibration and curve, in `[0, 1]`.
    public var normalized: Double
    /// Discrete level, `0` (idle) through `levelCount`.
    public var level: Int
    /// Level reported by the previous sample.
    public var previousLevel: Int
    /// AppKit pressure stage (0 = released, 1 = click, 2 = force click).
    public var stage: Int
    /// Event timestamp in seconds since boot (same clock as `ProcessInfo.systemUptime`).
    public var timestamp: TimeInterval

    public var levelChanged: Bool { level != previousLevel }

    public static let idle = PressureReading(raw: 0, normalized: 0, level: 0, previousLevel: 0, stage: 0, timestamp: 0)
}

/// Converts continuous pressure into discrete force levels.
///
/// Rising pressure moves up a level as soon as it enters the next band, so
/// there is no added latency. Falling pressure has to drop `hysteresis` below
/// the current band before the level goes down.
public struct PressureQuantizer {
    public var configuration: QuantizerConfiguration {
        didSet { configuration = configuration.sanitized() }
    }

    public private(set) var currentLevel = 0

    public init(configuration: QuantizerConfiguration = .default) {
        self.configuration = configuration.sanitized()
    }

    /// Applies calibration and the response curve to a raw pressure value.
    public func normalize(_ raw: Double) -> Double {
        let calibrated = min(max(raw / configuration.calibrationMax, 0), 1)
        return configuration.curve.apply(calibrated, strength: configuration.curveStrength)
    }

    /// The level a normalized value falls in, ignoring hysteresis.
    public func level(forNormalized value: Double) -> Int {
        let c = configuration
        // Tolerance so values sitting exactly on a boundary land in the upper band
        // despite floating-point error (0.15 - 0.05 is slightly less than 0.1).
        let epsilon = 1e-9
        if value < c.deadzone - epsilon { return 0 }
        if value >= c.ceiling - epsilon { return c.levelCount }
        let band = Int((value - c.deadzone) / c.bandWidth + epsilon)
        return min(max(band + 1, 1), c.levelCount - 1)
    }

    /// Processes one raw pressure sample and updates `currentLevel`.
    @discardableResult
    public mutating func process(_ raw: Double, stage: Int = 1, timestamp: TimeInterval = 0) -> PressureReading {
        process(raw: raw, normalized: normalize(raw), stage: stage, timestamp: timestamp)
    }

    /// Like `process(_:stage:timestamp:)`, but with an already-normalized
    /// depth, e.g. one built up over time by `HoldCharge`.
    @discardableResult
    public mutating func process(raw: Double, normalized: Double, stage: Int = 1, timestamp: TimeInterval = 0) -> PressureReading {
        let previous = currentLevel
        var level = level(forNormalized: normalized)

        if raw <= 0 || stage == 0 {
            level = 0
        } else if level < previous {
            // Only drop to the highest level whose band, widened by the
            // hysteresis margin, still contains the value.
            level = min(previous, self.level(forNormalized: normalized + configuration.hysteresis))
        }

        currentLevel = level
        return PressureReading(
            raw: raw,
            normalized: normalized,
            level: level,
            previousLevel: previous,
            stage: stage,
            timestamp: timestamp
        )
    }

    /// Returns to level 0, e.g. when the finger lifts.
    @discardableResult
    public mutating func reset(timestamp: TimeInterval = 0) -> PressureReading {
        process(0, stage: 0, timestamp: timestamp)
    }
}
