import {
  PressureQuantizer,
  PressureCalibrator,
  DEFAULT_CONFIG,
  webkitForceToRaw,
  invertCurve,
  lowerBound,
} from "./quantizer.js";

const $ = (id) => document.getElementById(id);

const SETTINGS_KEY = "force-touch-tracker:settings";
const CALIBRATION_MS = 4000;
const SIM_RAMP_PER_SECOND = 0.45;
const HISTORY_LENGTH = 240;

const quantizer = new PressureQuantizer(loadSettings());
const calibrator = new PressureCalibrator();

const els = {
  badge: $("source-badge"),
  level: $("level"),
  levelCount: $("level-count"),
  raw: $("raw"),
  normalized: $("normalized"),
  stage: $("stage"),
  peak: $("peak"),
  latency: $("latency"),
  bar: $("bar"),
  ringSegments: $("ring-segments"),
  ringLabel: $("ring-label"),
  pad: $("pad"),
  padTitle: $("pad-title"),
  history: $("history"),
  bands: $("bands"),
  curve: $("curve"),
  strength: $("strength"),
  deadzone: $("deadzone"),
  hysteresis: $("hysteresis"),
  calibrate: $("calibrate"),
  calibrationReset: $("calibration-reset"),
  calibrationOut: $("calibration-out"),
  sound: $("sound"),
  vibrate: $("vibrate"),
  manual: $("manual"),
  manualOut: $("manual-out"),
  clearPeak: $("clear-peak"),
};

const state = {
  reading: quantizer.reset(),
  peak: 0,
  pendingEventTime: null,
  latency: null,
  calibratingUntil: 0,
  dirty: true,
  renderedLevel: -1,
};

const sim = { held: false, raw: 0, lastTime: 0 };
const history = { normalized: new Float32Array(HISTORY_LENGTH), level: new Uint8Array(HISTORY_LENGTH), head: 0 };

const hasWebkitForce = typeof MouseEvent !== "undefined" && "WEBKIT_FORCE_AT_MOUSE_DOWN" in MouseEvent;
let forceHardwareSeen = false;
let pointerDown = false;

// ---------------------------------------------------------------- pipeline

function feed(raw, stage, eventTime, source) {
  const reading = quantizer.process(raw, stage, eventTime ?? 0);
  if (state.calibratingUntil) calibrator.record(raw);
  if (reading.levelChanged) onLevelChange(reading);
  state.reading = reading;
  state.peak = Math.max(state.peak, reading.level);
  if (eventTime != null) state.pendingEventTime = eventTime;
  state.dirty = true;
  if (source) setSource(source);
}

function release(eventTime) {
  if (quantizer.currentLevel === 0 && state.reading.raw === 0) return;
  feed(0, 0, eventTime, null);
}

function stageForRaw(raw) {
  if (raw <= 0) return 0;
  return raw < 0.5 ? 1 : 2;
}

// ---------------------------------------------------------------- feedback

let audio = null;

function unlockAudio() {
  if (!els.sound.checked || audio) return;
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (Ctx) audio = new Ctx();
}

function onLevelChange(reading) {
  const { level, previousLevel } = reading;
  if (level <= previousLevel) return;

  const seg = els.bar.children[level - 1];
  if (seg) {
    seg.classList.remove("pulse");
    void seg.offsetWidth; // restart the animation
    seg.classList.add("pulse");
  }

  if (els.vibrate.checked && navigator.vibrate) {
    navigator.vibrate(level === quantizer.config.levelCount ? 20 : 8);
  }

  if (els.sound.checked) {
    unlockAudio();
    if (audio) tick(level);
  }
}

function tick(level) {
  const t = audio.currentTime;
  const osc = audio.createOscillator();
  const gain = audio.createGain();
  osc.type = "sine";
  osc.frequency.value = 260 * Math.pow(2, (level - 1) / 6);
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(0.12, t + 0.004);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
  osc.connect(gain).connect(audio.destination);
  osc.start(t);
  osc.stop(t + 0.06);
}

// ---------------------------------------------------------------- input

function setSource(source) {
  const labels = {
    force: "Force Touch: live",
    pointer: "Pen / touch pressure",
    sim: "Simulated input",
    manual: "Manual input",
  };
  if (els.badge.dataset.state === source) return;
  els.badge.dataset.state = source;
  els.badge.textContent = labels[source] ?? source;
}

function initialBadge() {
  els.badge.dataset.state = "none";
  els.badge.textContent = hasWebkitForce
    ? "Safari: click the pad to detect Force Touch"
    : "No Force Touch in this browser. Use simulated input";
}

function startSim() {
  sim.held = true;
  sim.raw = 0;
  sim.lastTime = performance.now();
  setSource("sim");
}

function stopSim() {
  if (!sim.held) return;
  sim.held = false;
  sim.raw = 0;
  release(null);
}

const pad = els.pad;

// Safari on Force Touch Macs. Preventing the default stops the force click
// from opening Look Up or Quick Look.
pad.addEventListener("webkitmouseforcewillbegin", (e) => {
  forceHardwareSeen = true;
  e.preventDefault();
});
pad.addEventListener("webkitmouseforcedown", (e) => e.preventDefault());
pad.addEventListener("webkitmouseforcechanged", (e) => {
  forceHardwareSeen = true;
  if (sim.held) sim.held = false;
  const force = e.webkitForce;
  const stage = force < 1 ? 0 : force < 2 ? 1 : 2;
  feed(webkitForceToRaw(force), stage, e.timeStamp, "force");
});

// Pens and some touchscreens report pressure through Pointer Events. A
// pressure of exactly 0.5 means the device doesn't measure it.
function hasRealPressure(e) {
  return e.pointerType !== "mouse" && e.pressure > 0 && e.pressure !== 0.5;
}

pad.addEventListener("pointerdown", (e) => {
  pointerDown = true;
  pad.setPointerCapture?.(e.pointerId);
  pad.classList.add("active");
  unlockAudio();
  if (hasRealPressure(e)) {
    feed(e.pressure, 1, e.timeStamp, "pointer");
  } else if (!forceHardwareSeen) {
    startSim();
  }
});

pad.addEventListener("pointermove", (e) => {
  if (!pointerDown || !hasRealPressure(e)) return;
  if (sim.held) sim.held = false;
  feed(e.pressure, 1, e.timeStamp, "pointer");
});

function endPointer(e) {
  if (!pointerDown) return;
  pointerDown = false;
  pad.classList.remove("active");
  if (sim.held) {
    stopSim();
  } else {
    release(e.timeStamp);
  }
}
pad.addEventListener("pointerup", endPointer);
pad.addEventListener("pointercancel", endPointer);
pad.addEventListener("contextmenu", (e) => e.preventDefault());

function isTyping(target) {
  return target instanceof HTMLElement && target.matches("input, select, textarea, button");
}

document.addEventListener("keydown", (e) => {
  if (e.code !== "Space" || isTyping(e.target)) return;
  e.preventDefault();
  if (e.repeat || sim.held) return;
  unlockAudio();
  pad.classList.add("active");
  startSim();
});

document.addEventListener("keyup", (e) => {
  if (e.code !== "Space" || isTyping(e.target)) return;
  e.preventDefault();
  if (!pointerDown) pad.classList.remove("active");
  stopSim();
});

window.addEventListener("blur", () => {
  pointerDown = false;
  pad.classList.remove("active");
  stopSim();
});

els.manual.addEventListener("input", () => {
  const v = Number(els.manual.value);
  els.manualOut.textContent = v.toFixed(2);
  feed(v, stageForRaw(v), null, "manual");
});

// ---------------------------------------------------------------- settings

function loadSettings() {
  try {
    const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) || "{}");
    return { ...DEFAULT_CONFIG, ...saved };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function saveSettings() {
  try {
    const { curve, curveStrength, deadzone, hysteresis, calibrationMax } = quantizer.config;
    localStorage.setItem(SETTINGS_KEY, JSON.stringify({ curve, curveStrength, deadzone, hysteresis, calibrationMax }));
  } catch {
    // Storage unavailable; settings just won't persist.
  }
}

function syncControls() {
  const c = quantizer.config;
  els.curve.value = c.curve;
  els.strength.value = c.curveStrength;
  els.deadzone.value = c.deadzone;
  els.hysteresis.value = c.hysteresis;
  $("strength-out").textContent = c.curveStrength.toFixed(1);
  $("deadzone-out").textContent = c.deadzone.toFixed(2);
  $("hysteresis-out").textContent = c.hysteresis.toFixed(3);
  els.calibrationOut.textContent = c.calibrationMax.toFixed(2);
  els.strength.disabled = c.curve === "linear";
}

function configure(patch) {
  quantizer.configure(patch);
  syncControls();
  renderBands();
  saveSettings();
  state.dirty = true;
}

els.curve.addEventListener("change", () => configure({ curve: els.curve.value }));
els.strength.addEventListener("input", () => configure({ curveStrength: Number(els.strength.value) }));
els.deadzone.addEventListener("input", () => configure({ deadzone: Number(els.deadzone.value) }));
els.hysteresis.addEventListener("input", () => configure({ hysteresis: Number(els.hysteresis.value) }));
els.calibrationReset.addEventListener("click", () => configure({ calibrationMax: 1 }));
els.clearPeak.addEventListener("click", () => {
  state.peak = quantizer.currentLevel;
  state.dirty = true;
});
els.sound.addEventListener("change", unlockAudio);

els.calibrate.addEventListener("click", () => {
  calibrator.reset();
  state.calibratingUntil = performance.now() + CALIBRATION_MS;
  els.calibrate.disabled = true;
  pad.classList.add("calibrating");
  pad.focus();
});

function updateCalibration(now) {
  if (!state.calibratingUntil) return;
  const left = state.calibratingUntil - now;
  if (left > 0) {
    els.padTitle.textContent = `Calibrating: press as hard as is comfortable… ${Math.ceil(left / 1000)}s`;
    return;
  }
  state.calibratingUntil = 0;
  els.calibrate.disabled = false;
  pad.classList.remove("calibrating");
  els.padTitle.textContent = "Click and hold here, then press harder";
  const max = calibrator.recommendedCalibrationMax;
  if (max != null) configure({ calibrationMax: max });
}

// ---------------------------------------------------------------- rendering

function segmentColor(index, count) {
  const t = count > 1 ? index / (count - 1) : 0;
  return `hsl(${Math.round(140 * (1 - t))} 80% 52%)`;
}

function buildLoaders() {
  const count = quantizer.config.levelCount;
  els.bar.style.setProperty("--count", count);
  els.bar.setAttribute("aria-valuemax", count);
  els.levelCount.textContent = `/ ${count}`;
  els.bar.replaceChildren();
  els.ringSegments.replaceChildren();

  const cx = 100, cy = 100, r = 80, gapDeg = 4;
  for (let i = 0; i < count; i++) {
    const color = segmentColor(i, count);

    const seg = document.createElement("div");
    seg.className = "seg";
    seg.style.setProperty("--c", color);
    els.bar.append(seg);

    const a0 = ((i / count) * 360 + gapDeg / 2 - 90) * (Math.PI / 180);
    const a1 = (((i + 1) / count) * 360 - gapDeg / 2 - 90) * (Math.PI / 180);
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute(
      "d",
      `M ${cx + r * Math.cos(a0)} ${cy + r * Math.sin(a0)} A ${r} ${r} 0 0 1 ${cx + r * Math.cos(a1)} ${cy + r * Math.sin(a1)}`
    );
    path.style.setProperty("--c", color);
    els.ringSegments.append(path);
  }
  state.renderedLevel = -1;
}

function renderBands() {
  const c = quantizer.config;
  const rows = [];
  const rawFor = (v) => invertCurve(c.curve, v, c.curveStrength) * c.calibrationMax;
  rows.push(`<tr data-level="0"><td><span class="swatch"></span>0 · idle</td><td>&lt; ${c.deadzone.toFixed(2)}</td><td>&lt; ${rawFor(c.deadzone).toFixed(3)}</td></tr>`);
  for (let level = 1; level <= c.levelCount; level++) {
    const lo = lowerBound(c, level);
    const range = level === c.levelCount ? `≥ ${lo.toFixed(2)}` : `${lo.toFixed(2)} – ${lowerBound(c, level + 1).toFixed(2)}`;
    rows.push(
      `<tr data-level="${level}"><td><span class="swatch" style="--c:${segmentColor(level - 1, c.levelCount)}"></span>${level}${level === c.levelCount ? " · max" : ""}</td><td>${range}</td><td>≥ ${rawFor(lo).toFixed(3)}</td></tr>`
    );
  }
  els.bands.innerHTML = rows.join("");
  state.renderedLevel = -1;
}

function render() {
  const { reading } = state;
  els.raw.textContent = reading.raw.toFixed(3);
  els.normalized.textContent = reading.normalized.toFixed(3);
  els.stage.textContent = reading.stage;
  els.peak.textContent = state.peak;
  if (state.latency != null) els.latency.textContent = state.latency.toFixed(1);

  if (reading.level === state.renderedLevel) return;
  state.renderedLevel = reading.level;
  els.level.textContent = reading.level;
  els.ringLabel.textContent = reading.level;
  els.bar.setAttribute("aria-valuenow", reading.level);
  [...els.bar.children].forEach((seg, i) => seg.classList.toggle("on", i < reading.level));
  [...els.ringSegments.children].forEach((p, i) => p.classList.toggle("on", i < reading.level));
  for (const row of els.bands.rows) row.classList.toggle("current", Number(row.dataset.level) === reading.level);
}

let palette = readPalette();
window.matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", () => {
  palette = readPalette();
});

function readPalette() {
  const s = getComputedStyle(document.documentElement);
  return {
    grid: s.getPropertyValue("--border").trim(),
    line: s.getPropertyValue("--accent").trim(),
    muted: s.getPropertyValue("--muted").trim(),
  };
}

function drawHistory() {
  const canvas = els.history;
  const dpr = window.devicePixelRatio || 1;
  const w = Math.round(canvas.clientWidth * dpr);
  const h = Math.round(canvas.clientHeight * dpr);
  if (!w || !h) return;
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  const ctx = canvas.getContext("2d");
  const c = quantizer.config;
  const pad = 6 * dpr;
  const y = (v) => h - pad - v * (h - 2 * pad);
  const x = (i) => (i / (HISTORY_LENGTH - 1)) * w;

  ctx.clearRect(0, 0, w, h);

  ctx.strokeStyle = palette.grid;
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let level = 1; level <= c.levelCount; level++) {
    const yy = Math.round(y(lowerBound(c, level))) + 0.5;
    ctx.moveTo(0, yy);
    ctx.lineTo(w, yy);
  }
  ctx.stroke();

  // Level as a step line.
  ctx.strokeStyle = palette.muted;
  ctx.lineWidth = 1.5 * dpr;
  ctx.beginPath();
  for (let i = 0; i < HISTORY_LENGTH; i++) {
    const level = history.level[(history.head + i) % HISTORY_LENGTH];
    const yy = y(level === 0 ? 0 : lowerBound(c, level));
    if (i === 0) ctx.moveTo(x(i), yy);
    else ctx.lineTo(x(i), yy);
  }
  ctx.stroke();

  // Normalized pressure.
  ctx.strokeStyle = palette.line;
  ctx.lineWidth = 2 * dpr;
  ctx.beginPath();
  for (let i = 0; i < HISTORY_LENGTH; i++) {
    const v = history.normalized[(history.head + i) % HISTORY_LENGTH];
    if (i === 0) ctx.moveTo(x(i), y(v));
    else ctx.lineTo(x(i), y(v));
  }
  ctx.stroke();
}

function frame(now) {
  if (sim.held) {
    const dt = (now - sim.lastTime) / 1000;
    sim.lastTime = now;
    sim.raw = Math.min(1, sim.raw + dt * SIM_RAMP_PER_SECOND);
    feed(sim.raw, stageForRaw(sim.raw), null, null);
  }

  if (state.pendingEventTime != null) {
    const ms = now - state.pendingEventTime;
    if (ms >= 0 && ms < 1000) {
      state.latency = state.latency == null ? ms : state.latency * 0.85 + ms * 0.15;
    }
    state.pendingEventTime = null;
  }

  updateCalibration(now);

  if (state.dirty) {
    render();
    state.dirty = false;
  }

  history.normalized[history.head] = state.reading.normalized;
  history.level[history.head] = state.reading.level;
  history.head = (history.head + 1) % HISTORY_LENGTH;
  drawHistory();

  requestAnimationFrame(frame);
}

// ---------------------------------------------------------------- start

initialBadge();
buildLoaders();
syncControls();
renderBands();
render();
requestAnimationFrame(frame);
