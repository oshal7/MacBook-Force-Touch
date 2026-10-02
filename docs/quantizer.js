// JavaScript port of ForceTouchKit's quantizer. Keep in step with
// Sources/ForceTouchKit/PressureQuantizer.swift.

export const CURVES = ["linear", "exponential", "logarithmic"];

export const DEFAULT_CONFIG = Object.freeze({
  levelCount: 10,
  deadzone: 0.05,
  ceiling: 0.95,
  curve: "linear",
  curveStrength: 3,
  hysteresis: 0.02,
  calibrationMax: 1,
});

const clamp = (x, lo, hi) => Math.min(Math.max(x, lo), hi);
const EPSILON = 1e-9;

export function applyCurve(curve, x, strength) {
  x = clamp(x, 0, 1);
  const k = Math.max(strength, 0.0001);
  switch (curve) {
    case "exponential":
      return (Math.exp(k * x) - 1) / (Math.exp(k) - 1);
    case "logarithmic":
      return Math.log(1 + k * x) / Math.log(1 + k);
    default:
      return x;
  }
}

/** Inverse of `applyCurve`: the input that produces output `y`. */
export function invertCurve(curve, y, strength) {
  y = clamp(y, 0, 1);
  const k = Math.max(strength, 0.0001);
  switch (curve) {
    case "exponential":
      return Math.log(1 + y * (Math.exp(k) - 1)) / k;
    case "logarithmic":
      return (Math.pow(1 + k, y) - 1) / k;
    default:
      return y;
  }
}

export function sanitize(config) {
  const c = { ...DEFAULT_CONFIG, ...config };
  c.levelCount = Math.max(2, Math.round(c.levelCount));
  c.deadzone = clamp(c.deadzone, 0, 0.5);
  c.ceiling = clamp(c.ceiling, c.deadzone + 0.01, 1);
  c.curveStrength = clamp(c.curveStrength, 0.1, 10);
  c.hysteresis = clamp(c.hysteresis, 0, bandWidth(c));
  c.calibrationMax = clamp(c.calibrationMax, 0.05, 1);
  if (!CURVES.includes(c.curve)) c.curve = "linear";
  return c;
}

export function bandWidth(c) {
  return (c.ceiling - c.deadzone) / (c.levelCount - 1);
}

export function lowerBound(c, level) {
  if (level <= 0) return 0;
  return c.deadzone + (Math.min(level, c.levelCount) - 1) * bandWidth(c);
}

/** Joins AppKit's two pressure stages into one 0...1 range. */
export function stageCombined(pressure, stage) {
  const p = clamp(pressure, 0, 1);
  if (stage < 1) return 0;
  if (stage === 1) return p * 0.5;
  return 0.5 + p * 0.5;
}

/**
 * Converts Safari's `webkitForce` (1 = click, 2 = force click, 3 = max) to the
 * same 0...1 range as `stageCombined`.
 */
export function webkitForceToRaw(force) {
  return clamp((force - 1) / 2, 0, 1);
}

export class PressureQuantizer {
  constructor(config = {}) {
    this.config = sanitize(config);
    this.currentLevel = 0;
  }

  configure(patch) {
    this.config = sanitize({ ...this.config, ...patch });
  }

  normalize(raw) {
    const c = this.config;
    return applyCurve(c.curve, clamp(raw / c.calibrationMax, 0, 1), c.curveStrength);
  }

  levelFor(value) {
    const c = this.config;
    if (value < c.deadzone - EPSILON) return 0;
    if (value >= c.ceiling - EPSILON) return c.levelCount;
    const band = Math.floor((value - c.deadzone) / bandWidth(c) + EPSILON);
    return clamp(band + 1, 1, c.levelCount - 1);
  }

  process(raw, stage = 1, timestamp = 0) {
    const previousLevel = this.currentLevel;
    const normalized = this.normalize(raw);
    let level = this.levelFor(normalized);

    if (raw <= 0 || stage === 0) {
      level = 0;
    } else if (level < previousLevel) {
      level = Math.min(previousLevel, this.levelFor(normalized + this.config.hysteresis));
    }

    this.currentLevel = level;
    return {
      raw,
      normalized,
      level,
      previousLevel,
      stage,
      timestamp,
      levelChanged: level !== previousLevel,
    };
  }

  reset(timestamp = 0) {
    return this.process(0, 0, timestamp);
  }
}

export class PressureCalibrator {
  constructor({ headroom = 0.9, minimumMax = 0.2 } = {}) {
    this.headroom = headroom;
    this.minimumMax = minimumMax;
    this.reset();
  }

  record(raw) {
    if (!Number.isFinite(raw)) return;
    this.peak = Math.max(this.peak, raw);
    this.sampleCount += 1;
  }

  reset() {
    this.peak = 0;
    this.sampleCount = 0;
  }

  get recommendedCalibrationMax() {
    if (this.sampleCount === 0 || this.peak <= 0) return null;
    return clamp(this.peak * this.headroom, this.minimumMax, 1);
  }
}
