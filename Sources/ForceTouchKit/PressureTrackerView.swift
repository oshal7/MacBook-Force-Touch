#if canImport(AppKit)
import AppKit

/// An `NSView` that turns Force Touch trackpad pressure into discrete levels.
///
/// Click inside the view and press harder. Every pressure event goes through
/// the quantizer, plays a haptic on level changes, and is passed to
/// `onReading` on the main thread with no buffering.
@MainActor
open class PressureTrackerView: NSView {
    public var quantizer = PressureQuantizer()
    public var inputMapping: ForceInputMapping = .stageCombined
    public var haptics = LevelHaptics()

    /// Called for every processed pressure sample.
    public var onReading: (@MainActor (PressureReading) -> Void)?

    /// AppKit pressure behavior for clicks in this view. `.primaryDefault`
    /// gives a two-stage click / force click, which pairs with `.stageCombined`.
    /// `.primaryClick` has a single stage, so macOS shouldn't play its own
    /// force-click haptic over the level haptics; pair it with `.raw`.
    public var pressureBehavior: NSEvent.PressureBehavior = .primaryDefault {
        didSet { applyPressureConfiguration() }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyPressureConfiguration()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyPressureConfiguration()
    }

    open override var acceptsFirstResponder: Bool { true }
    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    open override func pressureChange(with event: NSEvent) {
        let raw = inputMapping.value(pressure: event.pressure, stage: event.stage)
        let reading = quantizer.process(raw, stage: event.stage, timestamp: event.timestamp)
        deliver(reading)
    }

    open override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard quantizer.currentLevel != 0 else { return }
        deliver(quantizer.reset(timestamp: event.timestamp))
    }

    private func deliver(_ reading: PressureReading) {
        haptics.handle(reading, levelCount: quantizer.configuration.levelCount)
        onReading?(reading)
    }

    private func applyPressureConfiguration() {
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: pressureBehavior)
    }
}
#endif
