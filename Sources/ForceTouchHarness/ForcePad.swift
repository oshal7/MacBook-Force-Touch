import ForceTouchKit
import SwiftUI

/// SwiftUI wrapper around `PressureTrackerView` that sends readings to the model.
struct ForcePad: NSViewRepresentable {
    @ObservedObject var model: HarnessModel

    func makeNSView(context: Context) -> PressureTrackerView {
        let view = PressureTrackerView(frame: .zero)
        view.haptics = model.haptics
        view.onReading = { [weak model] reading in
            model?.ingest(reading)
        }
        return view
    }

    func updateNSView(_ view: PressureTrackerView, context: Context) {
        view.quantizer.configuration = model.configuration
        view.inputMapping = model.pressureMode.mapping
        view.holdCharge.secondsToFull = model.secondsToFull
        if view.depthMode != model.depthMode {
            view.depthMode = model.depthMode
        }
        if view.pressureBehavior != model.pressureMode.behavior {
            view.pressureBehavior = model.pressureMode.behavior
        }
    }
}
