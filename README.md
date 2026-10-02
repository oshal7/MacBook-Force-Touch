# MacBook Force Touch: 10-Level Tracker

Reads continuous pressure from a MacBook's Force Touch trackpad and maps it to
**10 discrete force levels**, with a haptic pulse at each level and a 10-segment
loader to check the levels on real hardware.

- **`ForceTouchKit`**: Swift library with the quantizer, response curves,
  calibration, haptics, and a drop-in `PressureTrackerView`.
- **`ForceTouchHarness`**: SwiftUI test app with bar and ring loaders, live
  readouts, tuning controls, and real Taptic Engine feedback.
- **Web demo** (`docs/`): the same engine in JavaScript, hosted on GitHub Pages.
  It reads live Force Touch input in **Safari on a Force Touch Mac** and falls
  back to simulated input in other browsers.

**Live demo:** https://oshal7.github.io/MacBook-Force-Touch/

## Run the native harness

Requires macOS 11+ and Xcode 15+.

```sh
git clone https://github.com/oshal7/MacBook-Force-Touch.git
cd MacBook-Force-Touch
swift run ForceTouchHarness
```

Click inside the dashed pad and press harder. Each new level plays a haptic.

## Use the library

Add the package to your app (File → Add Package Dependencies…, or in `Package.swift`):

```swift
.package(url: "https://github.com/oshal7/MacBook-Force-Touch.git", branch: "main")
```

```swift
import ForceTouchKit

let tracker = PressureTrackerView()
tracker.quantizer.configuration.curve = .logarithmic
tracker.onReading = { reading in
    print(reading.level, reading.raw)   // 0–10, 0.0–1.0
}
```

The quantizer has no AppKit dependency, so you can feed it values from any source:

```swift
var q = PressureQuantizer()
q.process(0.42).level   // 4
```

## How it works

```
Trackpad ─► NSEvent (pressure, stage) ─► ForceInputMapping ─► PressureQuantizer ─┬─► LevelHaptics
                                         (join both stages)   (calibrate, curve, └─► onReading → UI
                                                               deadzone, bands,
                                                               hysteresis)
```

1. **Capture.** `PressureTrackerView.pressureChange(with:)` reads `pressure` and `stage`.
2. **Join stages.** With the default two-stage click, AppKit reports pressure
   0→1 for the click and then restarts at 0 for the force click.
   `.stageCombined` maps the click to 0–0.5 and the force click to 0.5–1, so
   the signal doesn't drop back at the force click.
3. **Quantize.** Pressure is divided by `calibrationMax`, shaped by the response
   curve, then split into bands:

   | Level | Normalized pressure |
   |-------|---------------------|
   | 0     | < 0.05 (deadzone)   |
   | 1     | 0.05 – 0.15         |
   | 2     | 0.15 – 0.25         |
   | …     | …                   |
   | 9     | 0.85 – 0.95         |
   | 10    | ≥ 0.95              |

   Rising pressure changes level immediately, with no added latency. Falling
   pressure has to drop `hysteresis` below the band before the level goes down,
   so the level doesn't flicker on a boundary.
4. **Haptics.** `LevelHaptics` plays a different haptic on entering each
   level (`LevelHapticProfile.escalating`):

   | Level | Haptic |
   |-------|--------|
   | 1–5   | One pulse each, getting stronger: light tap, weak click, medium tap, strong tap, strong click |
   | 6–8   | Double pulses: medium, strong tap, strong click |
   | 9     | Triple strong tap |
   | 10    | Buzz |

   By default it drives the trackpad actuator directly through the private
   `MultitouchSupport` framework (`MultitouchActuator`, the approach
   HapticKey uses). `NSHapticFeedbackManager` only has three patterns and
   tends to drop pulses during a click or force click. If the actuator can't
   be opened, it falls back to AppKit. The private API is fine for local
   tools but won't pass Mac App Store review.

   The browser can't drive the Taptic Engine at all. In the web demo, the
   only bumps you feel are macOS's own click and force click.

### Tuning

| Setting          | Default  | Purpose |
|------------------|----------|---------|
| `deadzone`       | 0.05     | Ignore light resting pressure |
| `ceiling`        | 0.95     | Pressure that reaches the top level |
| `curve`          | `.linear`| `.exponential` gives finer control at the top; `.logarithmic` lets light presses go further |
| `curveStrength`  | 3        | How far the curve bends |
| `hysteresis`     | 0.02     | Margin before a level drops |
| `calibrationMax` | 1.0      | Raw pressure that counts as full force |

`PressureCalibrator` records a few seconds of hard presses and recommends a
`calibrationMax` for that user. The harness and web demo both have a
**Calibrate** button.

### Latency

Each event is handled synchronously on the main thread, with no queues or
timers between the trackpad event and the UI update. The harness shows the
event-to-handler time, and the web demo shows event-to-frame time.

## Development

```sh
swift test                                  # Swift unit tests (macOS)
node --test web-tests/quantizer.test.mjs    # JS port tests
python3 -m http.server -d docs              # preview the web demo locally
```

`docs/quantizer.js` is a port of `Sources/ForceTouchKit/PressureQuantizer.swift`.
Keep the two in step; both test suites check the same cases.

## GitHub Pages

`.github/workflows/pages.yml` runs the JS tests and deploys `docs/` on every
push to the default branch that touches it. One-time setup: **Settings → Pages
→ Build and deployment → Source: GitHub Actions**.

## Roadmap

- Tune haptics so each of the 10 levels feels distinct on hardware.
- Use the engine for game mechanics: precision balancing, charge-up
  slingshots, variable jump height.
