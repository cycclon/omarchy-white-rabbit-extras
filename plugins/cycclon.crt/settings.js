// Helpers for the CRT overlay settings.

function clamp(v, lo, hi) {
  return Math.min(hi, Math.max(lo, v))
}

function num(v) {
  return typeof v === "number" && isFinite(v)
}

function fmt(n) {
  return String(Math.round(n * 1000) / 1000)
}