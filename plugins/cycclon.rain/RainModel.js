// Digital rain: column state machine and hidden-word scheduler.
//
// This file owns everything that has to be decided on the CPU. The renderer
// only ever asks two things of it: what glyphs does column N hold, and where
// is its drop right now.
//
// A column is a static strip of glyphs plus a drop -- a head position sliding
// down it at `speed` rows per second, trailing `trail` rows of fading light.
// When a drop runs off the bottom the column goes dark for a beat, then
// regenerates its glyphs and starts again. Glyphs are only rewritten between
// drops (plus a slow trickle of mutations) because every rewrite costs a Qt
// text relayout, and the film's rain does not re-roll its glyphs every frame
// either -- the trail reveals a fixed strip and then lets it fade.
//
// Hidden words are the reason the drops are scriptable at all. See
// scheduleWord() for how five columns are made to arrive at the same row at
// the same instant.

// --- glyph pool ------------------------------------------------------------

// Half-width katakana is the film's alphabet, but a field of nothing but
// katakana makes a five-letter Latin word scream the moment it lands. Digits
// and Latin are seeded through the noise at roughly the density the film uses
// so that a hidden word reads as more of the same until you look at it.
var KATAKANA = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ"
var DIGITS = "0123456789"
var LATIN = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
var SYMBOLS = ":=*+-<>|"

var POOL = (function () {
  var s = ""
  for (var i = 0; i < 6; i++) s += KATAKANA   // ~70%
  for (var j = 0; j < 3; j++) s += DIGITS     // ~17%
  s += LATIN                                  // ~10%
  s += SYMBOLS                                //  ~3%
  return s
})()

// --- word pool -------------------------------------------------------------

// Two registers, deliberately mixed: the machine you are actually running and
// the machine the theme is pretending to be. Long phrases are rarer by weight
// because a twenty-column alignment is a much bigger event than a five.
//
// The user's own list from ~/.config/omarchy/branding/rain-words.txt arrives
// through cfg.words and is what actually gets drawn from; this is the default
// half of it.
var BUILTIN_WORDS = [
  // the box
  "ARCH", "LINUX", "OMARCHY", "HYPRLAND", "WAYLAND", "QUICKSHELL",
  "PACMAN", "SYSTEMD", "KERNEL", "BTRFS", "NEOVIM", "TMUX", "BASH",
  "RUST", "RUBY", "GIT", "SUDO", "ROOT", "UEFI", "MESA", "VULKAN",
  "DAEMON", "SEGFAULT", "MAKEPKG", "AUR", "FOOT", "SSH", "TTY", "INIT",
  "FSTAB", "CHMOD", "DMESG", "SYSCALL", "EPOLL", "IOCTL", "MMAP",
  "STDERR", "FORK", "PIPE", "INODE", "SWAP", "GRUB", "RTFM",
  "KERNEL PANIC", "SEGMENTATION FAULT", "PERMISSION DENIED",
  "I USE ARCH BTW", "PID 1", "RM DASH RF",

  // the other one
  "NEO", "TRINITY", "MORPHEUS", "CYPHER", "TANK", "DOZER", "SWITCH",
  "APOC", "MOUSE", "ORACLE", "SMITH", "NIOBE", "SERAPH", "PERSEPHONE",
  "MEROVINGIAN", "KEYMAKER", "ARCHITECT", "TRAINMAN", "SATI", "BANE",
  "ZION", "NEBUCHADNEZZAR", "LOGOS", "CONSTRUCT", "DOJO", "SENTINEL",
  "AGENT", "MATRIX", "THE ONE", "DEJA VU", "WAKE UP", "RED PILL",
  "BLUE PILL", "KNOCK KNOCK", "SYSTEM FAILURE", "MACHINE CITY",
  "I KNOW KUNG FU", "DODGE THIS", "MR ANDERSON", "FREE YOUR MIND",
  "THERE IS NO SPOON", "FOLLOW THE WHITE RABBIT",
  "WELCOME TO THE REAL WORLD", "IGNORANCE IS BLISS",
  "THE DESERT OF THE REAL", "CALL TRANS OPT"
]

function randInt(n) { return Math.floor(Math.random() * n) }
function randRange(lo, hi) { return lo + Math.random() * (hi - lo) }
function randGlyph() { return POOL.charAt(randInt(POOL.length)) }

// --- field -----------------------------------------------------------------

function createField(cols, rows, cfg) {
  var field = {
    cols: cols,
    rows: rows,
    cfg: cfg,
    t: 0,
    columns: [],
    word: null,          // the alignment currently scheduled or fading
    recent: [],          // last few words used, to keep the pool from repeating
    nextWordAt: 0
  }

  for (var c = 0; c < cols; c++) {
    var col = {
      index: c,
      glyphs: new Array(rows),
      active: false,
      head: 0,
      speed: 0,
      trail: 0,
      bright: 0,
      wait: Math.random() * cfg.startSpread,
      scripted: null,
      dirty: true
    }
    fillGlyphs(col, rows)
    field.columns.push(col)
  }

  field.nextWordAt = cfg.wordEvery * randRange(0.3, 0.7)
  return field
}

// Run the field forward before anything is shown. A screensaver that fades
// in on a bare screen and then takes twelve seconds to fill looks like it is
// loading; the rain should already be falling when the fade lifts. Word
// scheduling is held off so the pre-roll cannot burn one unseen.
function preroll(field, seconds) {
  var step = 1 / 30
  var steps = Math.min(Math.round(seconds / step), 2000)

  field.nextWordAt = Infinity
  for (var i = 0; i < steps; i++) advance(field, step)
  field.nextWordAt = field.t + field.cfg.wordEvery * randRange(0.35, 0.9)
}

function fillGlyphs(col, rows) {
  for (var r = 0; r < rows; r++) col.glyphs[r] = randGlyph()
  col.dirty = true
}

// A drop's shape. Trails are long relative to the screen -- the film's
// columns are mostly trail -- and brightness varies so the field has depth
// instead of reading as one flat sheet.
function startDrop(field, col, script, overshoot) {
  var cfg = field.cfg
  fillGlyphs(col, field.rows)

  if (script) {
    col.speed = script.speed
    col.trail = script.trail
    col.bright = script.bright
    for (var i = 0; i < script.letters.length; i++) {
      var l = script.letters[i]
      if (l.row >= 0 && l.row < field.rows) col.glyphs[l.row] = l.ch
    }
  } else {
    col.speed = randRange(cfg.speedMin, cfg.speedMax) * cfg.speedScale
    col.trail = Math.round(randRange(cfg.trailMin, cfg.trailMax) * field.rows)
    col.bright = randRange(cfg.brightMin, 1.0)
  }

  // Frames land where they land; the cue does not. Starting the drop at the
  // distance it should already have covered keeps arrival times exact instead
  // of frame-quantised, which is what a five-column alignment is made of.
  col.head = overshoot > 0 ? overshoot * col.speed : 0
  col.active = true
  col.scripted = null
}

// Seconds until this column is free to take a scripted drop: the rest of the
// drop it is running, or the rest of the gap it is sitting out.
function freeIn(field, col) {
  if (!col.active) return Math.max(col.wait, 0)
  return Math.max(field.rows + col.trail - col.head, 0) / Math.max(col.speed, 0.001)
}

function advance(field, dt) {
  var cfg = field.cfg
  field.t += dt

  for (var c = 0; c < field.cols; c++) {
    var col = field.columns[c]

    if (col.active) {
      col.head += col.speed * dt
      if (col.head - col.trail > field.rows) {
        col.active = false
        col.wait = randRange(cfg.gapMin, cfg.gapMax)
      }
      continue
    }

    // A column holding a scripted drop waits for its exact cue; everything
    // else just counts down a random gap.
    if (col.scripted) {
      if (field.t >= col.scripted.start)
        startDrop(field, col, col.scripted, field.t - col.scripted.start)
      continue
    }

    col.wait -= dt
    if (col.wait <= 0) startDrop(field, col, null, -col.wait)
  }

  mutate(field, dt)
  tickWords(field)
}

// A slow trickle of in-place glyph changes. Enough to keep the field alive,
// few enough that the text relayouts stay in the noise.
function mutate(field, dt) {
  var n = field.cfg.mutationsPerSecond * dt
  var count = Math.floor(n) + (Math.random() < (n % 1) ? 1 : 0)

  for (var i = 0; i < count; i++) {
    var col = field.columns[randInt(field.cols)]
    var row = randInt(field.rows)
    // Never mutate a letter that a scheduled word is relying on.
    if (field.word && field.word.holds(col.index, row)) continue
    col.glyphs[row] = randGlyph()
    col.dirty = true
  }
}

// --- hidden words ----------------------------------------------------------

function wordPool(field) {
  var pool = field.cfg.words
  return pool && pool.length ? pool : BUILTIN_WORDS
}

function pickWord(field) {
  var pool = wordPool(field)

  for (var tries = 0; tries < 24; tries++) {
    var w = pool[randInt(pool.length)]
    // Long phrases take a bigger, rarer alignment to pull off.
    if (w.length > 10 && Math.random() > 0.35) continue
    if (w.length > 17 && Math.random() > 0.4) continue
    if (field.recent.indexOf(w) !== -1) continue
    if (w.length + 2 > field.cols) continue
    return w
  }

  // Nothing got through: either every entry is in the recent list, or the pool
  // is all phrases too wide for this screen. Fall back to anything that fits
  // rather than to a hardcoded word the user may have deliberately removed.
  for (var i = 0; i < pool.length; i++)
    if (pool[i].length + 2 <= field.cols) return pool[i]

  return ""
}

// How many words to remember before allowing a repeat. Fixed at a dozen this
// would deadlock a pool of four -- every candidate would be "too recent" --
// so it tracks the pool.
function remember(field, word) {
  var cap = Math.min(12, Math.floor(wordPool(field).length / 2))
  field.recent.push(word)
  while (field.recent.length > cap) field.recent.shift()
}

function tickWords(field) {
  var cfg = field.cfg

  // Retire an alignment once its glow has fully decayed. The letters stay in
  // the glyph strips and fade out with their trails, which is the point.
  if (field.word && field.t > field.word.tAlign + cfg.glowSigma * 4)
    field.word = null

  if (field.word || field.t < field.nextWordAt) return

  var word = pickWord(field)
  if (!word) {
    // Nothing in the pool fits this screen. Try again later rather than every
    // frame from here to the heat death of the universe.
    field.nextWordAt = field.t + cfg.wordEvery
    return
  }

  var vertical = word.indexOf(" ") === -1 &&
                 word.length <= Math.floor(field.rows * 0.4) &&
                 Math.random() < cfg.verticalChance

  if (vertical) scheduleVertical(field, word)
  else scheduleHorizontal(field, word)

  remember(field, word)
  field.nextWordAt = field.t + cfg.wordEvery * randRange(0.65, 1.45)
}

// Horizontal: one letter per column, and every participating column must put
// its head on the same row at the same instant.
//
// Each column gets its own fall speed, so the time it needs to reach the word
// row differs. Solving for a single arrival time means the slow columns are
// released first and the fast ones later; on screen the heads sweep down out
// of step, converge on one row, spell the word for a breath, and pull apart
// again as the faster columns run ahead.
function scheduleHorizontal(field, word, preempt) {
  var cfg = field.cfg
  var len = word.length
  var col0 = 1 + randInt(Math.max(field.cols - len - 2, 1))
  var row = Math.round(randRange(field.rows * 0.3, field.rows * 0.68))

  var plans = []
  var tAlign = 0
  var base = randRange(cfg.speedMin, cfg.speedMax) * cfg.speedScale

  for (var i = 0; i < len; i++) {
    var ch = word.charAt(i)
    if (ch === " ") continue

    var col = field.columns[col0 + i]
    var speed = base * randRange(0.7, 1.35)
    var travel = row / speed
    if (preempt) col.active = false
    tAlign = Math.max(tAlign, (preempt ? 0 : freeIn(field, col)) + travel)

    plans.push({ col: col, ch: ch, speed: speed, travel: travel })
  }

  if (!plans.length) return
  tAlign += 0.4

  for (var p = 0; p < plans.length; p++) {
    var plan = plans[p]
    plan.col.scripted = {
      start: field.t + tAlign - plan.travel,
      speed: plan.speed,
      trail: Math.round(randRange(cfg.trailMin, cfg.trailMax) * field.rows),
      bright: randRange(0.85, 1.0),
      letters: [{ row: row, ch: plan.ch }]
    }
  }

  field.word = makeWord(word, col0, col0 + len - 1, row, row, field.t + tAlign)
}

// Vertical: the word is written down a single column and revealed a letter at
// a time as the head passes over it. The trail is stretched past the word's
// length so the whole thing is lit at once by the time the head clears the
// last letter -- which is where the glow peaks.
function scheduleVertical(field, word, preempt) {
  var cfg = field.cfg
  var len = word.length
  var col = field.columns[1 + randInt(Math.max(field.cols - 2, 1))]
  var row0 = Math.round(randRange(field.rows * 0.2, field.rows * 0.55))
  var row1 = row0 + len - 1
  var speed = randRange(cfg.speedMin, cfg.speedMax) * cfg.speedScale * 0.8

  var letters = []
  for (var i = 0; i < len; i++) letters.push({ row: row0 + i, ch: word.charAt(i) })

  if (preempt) col.active = false
  var tAlign = (preempt ? 0 : freeIn(field, col)) + row1 / speed + 0.4
  col.scripted = {
    start: field.t + tAlign - row1 / speed,
    speed: speed,
    trail: Math.max(len + 6, Math.round(cfg.trailMin * field.rows)),
    bright: randRange(0.9, 1.0),
    letters: letters
  }

  field.word = makeWord(word, col.index, col.index, row0, row1, field.t + tAlign)
}

function makeWord(text, col0, col1, row0, row1, tAlign) {
  return {
    text: text,
    col0: col0, col1: col1,
    row0: row0, row1: row1,
    tAlign: tAlign,
    holds: function (c, r) {
      return c >= col0 && c <= col1 && r >= row0 && r <= row1
    }
  }
}

// Gaussian centred on the alignment: zero almost all the time, and the only
// thing that separates a hidden word from the rest of the rain.
function glowAt(field) {
  if (!field.word) return 0
  var k = (field.t - field.word.tAlign) / field.cfg.glowSigma
  return Math.exp(-k * k)
}

function forceWord(field, text, vertical) {
  var word = String(text || "").toUpperCase().replace(/[^A-Z0-9 ]/g, "")
  if (!word.length) return "nothing to spell"
  if (word.length + 2 > field.cols) return "too wide for this screen"

  field.word = null
  if (vertical && word.indexOf(" ") === -1 && word.length < field.rows * 0.5)
    scheduleVertical(field, word, true)
  else
    scheduleHorizontal(field, word, true)

  if (!field.word) return "could not schedule " + word
  field.nextWordAt = field.word.tAlign + field.cfg.wordEvery
  return word + " aligns in " + (field.word.tAlign - field.t).toFixed(1) + "s"
}
