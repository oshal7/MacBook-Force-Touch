import ForceTouchKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = HarnessModel()
    @State private var circular = false

    private var levelCount: Int { model.configuration.levelCount }
    /// Shows the haptic preview on the loader while it plays.
    private var displayLevel: Int { max(model.reading.level, model.previewLevel) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 20) {
                readouts
                Group {
                    if circular {
                        CircularSegmentLoader(level: displayLevel, count: levelCount)
                            .frame(width: 220, height: 220)
                    } else {
                        LinearSegmentLoader(level: displayLevel, count: levelCount)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 230)

                padArea
            }
            .padding(24)
            .frame(minWidth: 520)

            Divider()

            ScrollView {
                SettingsPanel(model: model, circular: $circular)
            }
            .frame(width: 300)
        }
        .frame(minHeight: 620)
    }

    private var readouts: some View {
        HStack(spacing: 28) {
            Metric(title: "LEVEL", value: "\(displayLevel)", suffix: "/ \(levelCount)", large: true)
            Metric(title: "RAW", value: String(format: "%.3f", model.reading.raw))
            Metric(title: "NORMALIZED", value: String(format: "%.3f", model.reading.normalized))
            Metric(title: "STAGE", value: "\(model.reading.stage)")
            Metric(title: "PEAK", value: "\(model.peakLevel)")
            Metric(title: "EVENT → HANDLER", value: String(format: "%.1f", model.latencyMs), suffix: "ms")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var padArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            VStack(spacing: 6) {
                Text(model.isCalibrating
                     ? "Calibrating: press as hard as is comfortable… \(model.calibrationSecondsLeft)s"
                     : "Click and hold here, then press harder")
                    .font(.headline)
                Text("Each new level plays a haptic. Lift your finger to reset.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .allowsHitTesting(false)
            ForcePad(model: model)
        }
        .frame(minHeight: 200)
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var suffix: String = ""
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: large ? 40 : 20, weight: .semibold, design: .monospaced))
                if !suffix.isEmpty {
                    Text(suffix).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct SettingsPanel: View {
    @ObservedObject var model: HarnessModel
    @Binding var circular: Bool

    var body: some View {
        Form {
            Section(header: Text("Display")) {
                Picker("Loader", selection: $circular) {
                    Text("Bar").tag(false)
                    Text("Ring").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section(header: Text("Response curve")) {
                Picker("Curve", selection: $model.configuration.curve) {
                    ForEach(PressureCurve.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                LabeledSlider(title: "Strength", value: $model.configuration.curveStrength, range: 0.5...8)
                LabeledSlider(title: "Deadzone", value: $model.configuration.deadzone, range: 0...0.2)
                LabeledSlider(title: "Hysteresis", value: $model.configuration.hysteresis, range: 0...0.08)
            }

            Section(header: Text("Input")) {
                Picker("Click", selection: $model.pressureMode) {
                    Text("Click + force click").tag(PressureMode.twoStage)
                    Text("Single stage").tag(PressureMode.singleStage)
                }
                Text(model.pressureMode == .twoStage
                     ? "macOS adds its own bump at the click and the force click."
                     : "No force click, so only the click bump comes from macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Haptics")) {
                Toggle("Haptic per level", isOn: $model.hapticsEnabled)
                Toggle("Haptic on step down", isOn: $model.hapticsOnRelease)
                Picker("Engine", selection: $model.hapticEngine) {
                    Text("Trackpad actuator").tag(LevelHaptics.Engine.trackpadActuator)
                    Text("AppKit").tag(LevelHaptics.Engine.appKit)
                }
                Picker("Pattern", selection: $model.hapticProfile) {
                    Text("Escalating").tag(HapticProfileChoice.escalating)
                    Text("Same every level").tag(HapticProfileChoice.uniform)
                }
                Text(model.isActuatorAvailable
                     ? "Trackpad actuator ready."
                     : "Trackpad actuator unavailable. Using AppKit haptics.")
                    .font(.caption)
                    .foregroundColor(model.isActuatorAvailable ? .secondary : .orange)
                Button(model.previewLevel > 0 ? "Playing level \(model.previewLevel)…" : "Preview all 10 levels") {
                    model.previewHaptics()
                }
                .disabled(model.previewLevel > 0)
                Text("Rest a finger on the trackpad while the preview plays.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Calibration")) {
                Text(String(format: "Full force = raw %.2f", model.configuration.calibrationMax))
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Calibrate") { model.startCalibration() }
                        .disabled(model.isCalibrating)
                    Button("Reset") { model.resetCalibration() }
                    Button("Clear peak") { model.resetPeak() }
                }
            }
        }
        .padding(16)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value)).font(.system(.caption, design: .monospaced))
            }
            Slider(value: $value, in: range)
        }
    }
}
