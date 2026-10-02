import Foundation

/// Response curve applied to calibrated pressure before it is split into levels.
///
/// - `linear`: pressure maps 1:1 onto the level bands.
/// - `exponential`: low pressures are compressed, giving finer control at the top
///   of the range. Good for users who press hard.
/// - `logarithmic`: low pressures are expanded, so light presses reach higher
///   levels. Good for users with less finger strength.
public enum PressureCurve: String, CaseIterable, Codable, Identifiable {
    case linear
    case exponential
    case logarithmic

    public var id: String { rawValue }

    /// Maps `x` in `[0, 1]` to `[0, 1]`. `strength` controls how far the curve
    /// bends away from linear; it is ignored for `.linear`.
    public func apply(_ x: Double, strength: Double) -> Double {
        let x = min(max(x, 0), 1)
        let k = max(strength, 0.0001)
        switch self {
        case .linear:
            return x
        case .exponential:
            return (exp(k * x) - 1) / (exp(k) - 1)
        case .logarithmic:
            return log(1 + k * x) / log(1 + k)
        }
    }
}
