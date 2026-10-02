import ForceTouchKit
import SwiftUI

/// SwiftUI wrapper around `PressureTrackerView` that sends readings to the model.
struct ForcePad: NSViewRepresentable {
    @ObservedObject var model: HarnessModel

    func makeNSView(context: Context) -> PressureTrackerView {
        let view = PressureTrackerView(frame: .zero)
        view.onReading = { [weak model] reading in
            model?.ingest(reading)
        }
        return view
    }

    func updateNSView(_ view: PressureTrackerView, context: Context) {
        view.quantizer.configuration = model.configuration
        view.inputMapping = model.inputMapping
        view.haptics.isEnabled = model.hapticsEnabled
        view.haptics.playsOnRelease = model.hapticsOnRelease
    }
}
