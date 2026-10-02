import Foundation

/// How AppKit's `pressure` and `stage` values become one continuous signal.
///
/// With the default pressure behavior, AppKit reports pressure `0...1` during
/// stage 1 (click), then restarts at `0` for stage 2 (force click). Using only
/// `pressure` would make the signal jump back down at the force click.
public enum ForceInputMapping: String, CaseIterable, Codable, Identifiable {
    /// Joins both stages into one `0...1` range: stage 1 covers `0..<0.5`
    /// and stage 2 covers `0.5...1`.
    case stageCombined
    /// Uses `pressure` as-is. Suits behaviors that report a single stage.
    case raw

    public var id: String { rawValue }

    public func value(pressure: Float, stage: Int) -> Double {
        let p = min(max(Double(pressure), 0), 1)
        switch self {
        case .raw:
            return stage <= 0 ? 0 : p
        case .stageCombined:
            switch stage {
            case ..<1: return 0
            case 1: return p * 0.5
            default: return 0.5 + p * 0.5
            }
        }
    }
}
