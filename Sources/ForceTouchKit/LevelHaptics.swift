#if canImport(AppKit)
import AppKit

/// Plays a Force Touch haptic each time the level changes.
///
/// macOS offers three patterns (`.generic`, `.alignment`, `.levelChange`). By
/// default each step up plays `.alignment`, the top level plays
/// `.levelChange`, and steps down are silent. Haptics only play while a finger
/// is on the trackpad.
@MainActor
public final class LevelHaptics {
    public var isEnabled = true
    public var playsOnRelease = false

    public var stepUpPattern: NSHapticFeedbackManager.FeedbackPattern = .alignment
    public var topLevelPattern: NSHapticFeedbackManager.FeedbackPattern = .levelChange
    public var stepDownPattern: NSHapticFeedbackManager.FeedbackPattern = .generic

    private let performer: NSHapticFeedbackPerformer

    public init(performer: NSHapticFeedbackPerformer? = nil) {
        self.performer = performer ?? NSHapticFeedbackManager.defaultPerformer
    }

    /// Plays the right pattern for `reading` if its level changed.
    public func handle(_ reading: PressureReading, levelCount: Int) {
        guard isEnabled, reading.levelChanged, reading.level > 0 else { return }

        if reading.level > reading.previousLevel {
            let pattern = reading.level >= levelCount ? topLevelPattern : stepUpPattern
            performer.perform(pattern, performanceTime: .now)
        } else if playsOnRelease {
            performer.perform(stepDownPattern, performanceTime: .now)
        }
    }
}
#endif
