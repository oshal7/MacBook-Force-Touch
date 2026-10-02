// Run with: node --test web-tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PressureQuantizer,
  PressureCalibrator,
  applyCurve,
  invertCurve,
  stageCombined,
  webkitForceToRaw,
  CURVES,
} from "../docs/quantizer.js";

test("default bands match the spec", () => {
  const q = new PressureQuantizer();
  const cases = [
    [0, 0], [0.049, 0],
    [0.05, 1], [0.149, 1],
    [0.15, 2], [0.25, 3], [0.35, 4], [0.45, 5],
    [0.55, 6], [0.65, 7], [0.75, 8], [0.85, 9], [0.949, 9],
    [0.95, 10], [1, 10],
  ];
  for (const [value, expected] of cases) {
    assert.equal(q.levelFor(value), expected, `pressure ${value}`);
  }
});

test("rising pressure steps through every level", () => {
  const q = new PressureQuantizer();
  const seen = [];
  for (let i = 0; i <= 100; i++) {
    const { level } = q.process(i / 100);
    if (seen.at(-1) !== level) seen.push(level);
  }
  assert.deepEqual(seen, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
});

test("hysteresis holds the level near a boundary", () => {
  const q = new PressureQuantizer({ hysteresis: 0.02 });
  assert.equal(q.process(0.36).level, 4);
  assert.equal(q.process(0.34).level, 4);
  assert.equal(q.process(0.32).level, 3);
  assert.equal(q.process(0.35).level, 4);
});

test("large drops skip levels and release resets", () => {
  const q = new PressureQuantizer();
  q.process(0.9);
  assert.equal(q.process(0.2).level, 2);
  const r = q.reset();
  assert.equal(r.level, 0);
  assert.equal(r.previousLevel, 2);
  assert.ok(r.levelChanged);
});

test("calibration scales raw pressure", () => {
  const q = new PressureQuantizer({ calibrationMax: 0.5 });
  assert.equal(q.process(0.5).level, 10);
  assert.equal(q.process(0.25).level, 5);
});

test("curves are monotonic and hit their endpoints", () => {
  for (const curve of CURVES) {
    assert.ok(Math.abs(applyCurve(curve, 0, 3)) < 1e-12);
    assert.ok(Math.abs(applyCurve(curve, 1, 3) - 1) < 1e-12);
    let last = -1;
    for (let i = 0; i <= 50; i++) {
      const y = applyCurve(curve, i / 50, 3);
      assert.ok(y >= last);
      last = y;
    }
  }
  for (const curve of CURVES) {
    for (const x of [0, 0.1, 0.35, 0.8, 1]) {
      assert.ok(Math.abs(invertCurve(curve, applyCurve(curve, x, 3), 3) - x) < 1e-9);
    }
  }
  assert.ok(applyCurve("exponential", 0.5, 3) < 0.5);
  assert.ok(applyCurve("logarithmic", 0.5, 3) > 0.5);
});

test("stage mapping is continuous across the force click", () => {
  assert.equal(stageCombined(0.5, 0), 0);
  assert.equal(stageCombined(1, 1), 0.5);
  assert.equal(stageCombined(0, 2), 0.5);
  assert.equal(stageCombined(1, 2), 1);
  assert.equal(webkitForceToRaw(0.5), 0);
  assert.equal(webkitForceToRaw(2), 0.5);
  assert.equal(webkitForceToRaw(3), 1);
});

test("calibrator recommends the peak with headroom", () => {
  const c = new PressureCalibrator({ headroom: 0.9, minimumMax: 0.2 });
  assert.equal(c.recommendedCalibrationMax, null);
  [0.1, 0.6, 0.4].forEach((v) => c.record(v));
  assert.ok(Math.abs(c.recommendedCalibrationMax - 0.54) < 1e-9);
  c.reset();
  c.record(0.05);
  assert.equal(c.recommendedCalibrationMax, 0.2);
});

test("configuration is sanitized", () => {
  const q = new PressureQuantizer();
  q.configure({ deadzone: -1, calibrationMax: 0, curve: "bogus" });
  assert.equal(q.config.deadzone, 0);
  assert.equal(q.config.calibrationMax, 0.05);
  assert.equal(q.config.curve, "linear");
});
