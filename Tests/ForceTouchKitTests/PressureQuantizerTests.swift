import XCTest
@testable import ForceTouchKit

final class PressureQuantizerTests: XCTestCase {
    func testDefaultBandsMatchSpec() {
        let q = PressureQuantizer()
        let cases: [(Double, Int)] = [
            (0.00, 0), (0.049, 0),
            (0.05, 1), (0.149, 1),
            (0.15, 2), (0.25, 3), (0.35, 4), (0.45, 5),
            (0.55, 6), (0.65, 7), (0.75, 8), (0.85, 9), (0.949, 9),
            (0.95, 10), (1.0, 10),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(q.level(forNormalized: value), expected, "pressure \(value)")
        }
    }

    func testRisingPressureStepsThroughEveryLevel() {
        var q = PressureQuantizer()
        var seen: [Int] = []
        for i in 0...100 {
            let level = q.process(Double(i) / 100).level
            if seen.last != level { seen.append(level) }
        }
        XCTAssertEqual(seen, Array(0...10))
    }

    func testHysteresisHoldsLevelNearBoundary() {
        var q = PressureQuantizer(configuration: QuantizerConfiguration(hysteresis: 0.02))
        XCTAssertEqual(q.process(0.36).level, 4)
        // Just below the level-4 boundary (0.35) but within the margin.
        XCTAssertEqual(q.process(0.34).level, 4)
        // Clearly below the margin.
        XCTAssertEqual(q.process(0.32).level, 3)
        // Rising is immediate.
        XCTAssertEqual(q.process(0.35).level, 4)
    }

    func testLargeDropSkipsLevels() {
        var q = PressureQuantizer()
        q.process(0.9)
        XCTAssertEqual(q.process(0.2).level, 2)
    }

    func testReleaseResetsToZero() {
        var q = PressureQuantizer()
        q.process(0.7)
        let reading = q.reset()
        XCTAssertEqual(reading.level, 0)
        XCTAssertEqual(reading.previousLevel, 7)
        XCTAssertTrue(reading.levelChanged)
    }

    func testCalibrationScalesRawPressure() {
        var q = PressureQuantizer(configuration: QuantizerConfiguration(calibrationMax: 0.5))
        XCTAssertEqual(q.process(0.5).level, 10)
        XCTAssertEqual(q.process(0.25).level, 5)
    }

    func testCurvesStayInRangeAndHitEndpoints() {
        for curve in PressureCurve.allCases {
            XCTAssertEqual(curve.apply(0, strength: 3), 0, accuracy: 1e-12)
            XCTAssertEqual(curve.apply(1, strength: 3), 1, accuracy: 1e-12)
            var last = -1.0
            for i in 0...50 {
                let y = curve.apply(Double(i) / 50, strength: 3)
                XCTAssertGreaterThanOrEqual(y, last)
                last = y
            }
        }
        XCTAssertLessThan(PressureCurve.exponential.apply(0.5, strength: 3), 0.5)
        XCTAssertGreaterThan(PressureCurve.logarithmic.apply(0.5, strength: 3), 0.5)
    }

    func testStageCombinedMappingIsContinuousAcrossForceClick() {
        let m = ForceInputMapping.stageCombined
        XCTAssertEqual(m.value(pressure: 0.5, stage: 0), 0)
        XCTAssertEqual(m.value(pressure: 1, stage: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.value(pressure: 0, stage: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.value(pressure: 1, stage: 2), 1, accuracy: 1e-9)
    }

    func testCalibratorRecommendsPeakWithHeadroom() {
        var c = PressureCalibrator(headroom: 0.9, minimumMax: 0.2)
        XCTAssertNil(c.recommendedCalibrationMax)
        [0.1, 0.6, 0.4].forEach { c.record($0) }
        XCTAssertEqual(c.recommendedCalibrationMax ?? 0, 0.54, accuracy: 1e-9)
        c.reset()
        c.record(0.05)
        XCTAssertEqual(c.recommendedCalibrationMax ?? 0, 0.2, accuracy: 1e-9)
    }

    func testConfigurationIsSanitized() {
        var q = PressureQuantizer()
        q.configuration.deadzone = -1
        q.configuration.calibrationMax = 0
        XCTAssertEqual(q.configuration.deadzone, 0)
        XCTAssertEqual(q.configuration.calibrationMax, 0.05)
    }
}
