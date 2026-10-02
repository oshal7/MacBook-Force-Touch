import Foundation

/// Makes depth build up the longer a press is held, so one continuous hold
/// steps through every level.
///
/// While held, the charge rises steadily: it takes `secondsToFull` to fill at
/// the lightest click, and pressing harder fills it faster. The reported depth
/// is whichever is greater, the charge or the current pressure, so a hard
/// press still jumps straight to a deep level. Releasing resets it.
public struct HoldCharge: Equatable {
    /// Time to reach full depth at the lightest click.
    public var secondsToFull: Double
    /// How much faster a full-force press charges: at full pressure the
    /// rate is `1 + pressureBoost` times the light-click rate.
    public var pressureBoost: Double

    public private(set) var value: Double = 0

    public init(secondsToFull: Double = 3, pressureBoost: Double = 2) {
        self.secondsToFull = secondsToFull
        self.pressureBoost = pressureBoost
    }

    /// Advances the charge by `dt` seconds and returns the depth in `[0, 1]`.
    /// `pressure` is the normalized pressure; `isHeld` is false once the click ends.
    public mutating func advance(pressure: Double, isHeld: Bool, dt: TimeInterval) -> Double {
        guard isHeld else {
            value = 0
            return 0
        }
        let p = min(max(pressure, 0), 1)
        let rate = (1 + max(pressureBoost, 0) * p) / max(secondsToFull, 0.1)
        value = min(1, value + rate * max(dt, 0))
        return max(value, p)
    }

    public mutating func reset() {
        value = 0
    }
}
