#if canImport(AppKit)
import AppKit

/// An `NSView` that turns Force Touch trackpad pressure into discrete levels.
///
/// Click inside the view and press harder. Every pressure event goes through
/// the quantizer, plays haptics on level changes, and is passed to
/// `onReading` on the main thread with no buffering.
@MainActor
open class PressureTrackerView: NSView {
    /// What decides how deep a press is.
    public enum DepthMode: String, CaseIterable, Identifiable {
        /// Level follows pressure only.
        case pressure
        /// Level also builds up the longer the click is held (see `HoldCharge`),
        /// so one long hold walks through every level.
        case holdToCharge

        public var id: String { rawValue }
    }

    public var quantizer = PressureQuantizer()
    public var inputMapping: ForceInputMapping = .stageCombined
    public var haptics = LevelHaptics()

    public var depthMode: DepthMode = .pressure {
        didSet { if depthMode != oldValue { endPress(timestamp: ProcessInfo.processInfo.systemUptime) } }
    }
    public var holdCharge = HoldCharge()

    /// Called for every processed sample.
    public var onReading: (@MainActor (PressureReading) -> Void)?

    /// AppKit pressure behavior for clicks in this view. `.primaryDefault`
    /// gives a two-stage click / force click, which pairs with `.stageCombined`.
    /// `.primaryClick` has a single stage, so macOS shouldn't play its own
    /// force-click haptic over the level haptics; pair it with `.raw`.
    public var pressureBehavior: NSEvent.PressureBehavior = .primaryDefault {
        didSet { applyPressureConfiguration() }
    }

    private var lastRaw: Double = 0
    private var lastStage = 0
    private var chargeTimer: Timer?
    private var lastTick: TimeInterval = 0

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
        lastRaw = raw
        lastStage = event.stage

        switch depthMode {
        case .pressure:
            deliver(quantizer.process(raw, stage: event.stage, timestamp: event.timestamp))
        case .holdToCharge:
            if event.stage >= 1 {
                if chargeTimer == nil { startCharging(timestamp: event.timestamp) }
                tick(now: event.timestamp)
            } else {
                endPress(timestamp: event.timestamp)
            }
        }
    }

    open override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        endPress(timestamp: event.timestamp)
    }

    // MARK: - Hold to charge

    private func startCharging(timestamp: TimeInterval) {
        holdCharge.reset()
        lastTick = timestamp
        // Common run loop modes keep it ticking while AppKit tracks the click.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: ProcessInfo.processInfo.systemUptime) }
        }
        RunLoop.main.add(timer, forMode: .common)
        chargeTimer = timer
    }

    private func tick(now: TimeInterval) {
        guard chargeTimer != nil else { return }
        let dt = max(now - lastTick, 0)
        lastTick = now
        let depth = holdCharge.advance(pressure: quantizer.normalize(lastRaw), isHeld: lastStage >= 1, dt: dt)
        deliver(quantizer.process(raw: lastRaw, normalized: depth, stage: lastStage, timestamp: now))
    }

    private func endPress(timestamp: TimeInterval) {
        chargeTimer?.invalidate()
        chargeTimer = nil
        holdCharge.reset()
        lastRaw = 0
        lastStage = 0
        haptics.stop()
        guard quantizer.currentLevel != 0 else { return }
        deliver(quantizer.reset(timestamp: timestamp))
    }

    // MARK: -

    private func deliver(_ reading: PressureReading) {
        haptics.handle(reading, levelCount: quantizer.configuration.levelCount)
        onReading?(reading)
    }

    private func applyPressureConfiguration() {
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: pressureBehavior)
    }
}
#endif
