// fe-auth: browser glue for the Elm auth pages (Signup / Login / Invite).
//
// Ports of the small JS behaviors those pages used as LiveView hooks in
// app.js — clipboard copy (CopyToken), select-on-focus for the readonly
// token field (was an inline onfocus, which Elm's virtual-dom strips),
// and the OrganicCanvas / MatrixCanvas auth backgrounds, booted by a
// MutationObserver instead of hook lifecycles.
//
// Owned by the fe-auth page agent. Imported from spa.js.

// --- Clipboard copy for [data-copy-target] buttons -------------------
// The Elm side owns the "Copied ✓" label / copy-gate state via onClick;
// this handler only performs the actual clipboard write.
document.addEventListener("click", async (e) => {
  const btn = e.target.closest("[data-copy-target]")
  if (!btn) return
  const target = document.querySelector(btn.dataset.copyTarget)
  if (!target) return
  const text =
    target.tagName === "INPUT" || target.tagName === "TEXTAREA"
      ? target.value.trim()
      : target.textContent.trim()
  try {
    await navigator.clipboard.writeText(text)
  } catch (err) {
    // Selection-based fallback, mirroring the CopyToken hook.
    try {
      if (target.select) {
        target.focus()
        target.select()
      } else {
        const range = document.createRange()
        range.selectNodeContents(target)
        const sel = window.getSelection()
        sel.removeAllRanges()
        sel.addRange(range)
      }
      document.execCommand("copy")
    } catch (err2) {
      // Leave the text selected so the user can copy manually.
    }
  }
})

// --- Select-on-focus for the readonly token field --------------------
document.addEventListener("focusin", (e) => {
  const el = e.target
  if (el.classList && el.classList.contains("token-field-input") && el.select) {
    el.select()
  }
})

// --- Auth background canvases ----------------------------------------
// Same animation code as the OrganicCanvas / MatrixCanvas hooks in
// app.js; each start function cleans itself up when its canvas leaves
// the DOM (checked on every frame + resize).

function withLifecycle(canvas, { resize, tick }) {
  let raf = 0

  const start = () => {
    if (!raf) raf = requestAnimationFrame(frame)
  }
  const stop = () => {
    if (raf) cancelAnimationFrame(raf)
    raf = 0
  }

  const cleanup = () => {
    stop()
    window.removeEventListener("resize", onResize)
    document.removeEventListener("visibilitychange", onVis)
  }

  const frame = () => {
    raf = 0
    if (!canvas.isConnected) return cleanup()
    tick()
    start()
  }

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
  const obey = () => {
    stop()
    if (!reduced.matches) start()
  }

  const onResize = () => {
    if (!canvas.isConnected) return cleanup()
    resize()
  }
  const onVis = () => {
    if (document.hidden) stop()
    else obey()
  }

  window.addEventListener("resize", onResize)
  document.addEventListener("visibilitychange", onVis)

  resize()
  obey()
}

function startOrganic(canvas) {
  const ctx = canvas.getContext("2d")
  const DPR = Math.min(window.devicePixelRatio || 1, 2)
  let w = 0, h = 0, t = 0, motes = []

  const resize = () => {
    w = canvas.parentElement.clientWidth
    h = canvas.parentElement.clientHeight
    canvas.width = w * DPR; canvas.height = h * DPR
    canvas.style.width = w + "px"; canvas.style.height = h + "px"
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0)
    motes = []
    const count = Math.round((w * h) / 22000)
    for (let i = 0; i < count; i++) {
      motes.push({
        x: Math.random() * w, y: Math.random() * h,
        r: 1 + Math.random() * 2.5,
        vx: (Math.random() - 0.5) * 0.08,
        vy: (Math.random() - 0.5) * 0.08,
        phase: Math.random() * Math.PI * 2,
        freq: 0.005 + Math.random() * 0.008,
        alpha: 0.06 + Math.random() * 0.1,
      })
    }
  }

  const tick = () => {
    ctx.clearRect(0, 0, w, h)
    t += 1
    for (let band = 0; band < 4; band++) {
      const yBase = h * (0.18 + band * 0.2)
      const amp = h * 0.08
      const speed = t * 0.005 * (band + 1) * 0.4
      ctx.beginPath()
      for (let x = 0; x <= w; x += 4) {
        const y = yBase +
          Math.sin((x / (140 + band * 60)) + speed + band) * amp +
          Math.sin((x / 320) + speed * 0.5) * (amp * 0.35)
        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = "rgba(26,20,16," + (0.13 - band * 0.02) + ")"
      ctx.lineWidth = 1.15
      ctx.stroke()
    }
    for (const m of motes) {
      m.phase += m.freq
      m.x += m.vx + Math.cos(m.phase) * 0.2
      m.y += m.vy + Math.sin(m.phase) * 0.15
      if (m.x < -10) m.x = w + 10
      else if (m.x > w + 10) m.x = -10
      if (m.y < -10) m.y = h + 10
      else if (m.y > h + 10) m.y = -10
      ctx.fillStyle = "rgba(26,20,16," + (m.alpha + 0.03) + ")"
      ctx.beginPath()
      ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  withLifecycle(canvas, { resize, tick })
}

function startMatrix(canvas) {
  const ctx = canvas.getContext("2d")
  const DPR = Math.min(window.devicePixelRatio || 1, 2)
  const FONT_SIZE = 14
  const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{}[]<>=/+-*?!#$%&"
  let w = 0, h = 0, drops = []

  const resize = () => {
    w = canvas.parentElement.clientWidth
    h = canvas.parentElement.clientHeight
    canvas.width = w * DPR; canvas.height = h * DPR
    canvas.style.width = w + "px"; canvas.style.height = h + "px"
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0)
    const cols = Math.ceil(w / FONT_SIZE)
    drops = new Array(cols).fill(0).map(() => ({
      y: -Math.random() * h,
      speed: 0.4 + Math.random() * 1.0,
      len: 8 + Math.floor(Math.random() * 18),
    }))
  }

  const tick = () => {
    ctx.fillStyle = "rgba(8,8,10,0.24)"
    ctx.fillRect(0, 0, w, h)
    ctx.font = FONT_SIZE + "px 'JetBrains Mono', monospace"
    ctx.textBaseline = "top"
    for (let i = 0; i < drops.length; i++) {
      const d = drops[i]
      const x = i * FONT_SIZE
      const headChar = CHARS[(Math.random() * CHARS.length) | 0]
      ctx.fillStyle = "rgba(245,245,245,0.55)"
      ctx.fillText(headChar, x, d.y)
      for (let k = 1; k < d.len; k++) {
        const yy = d.y - k * FONT_SIZE
        if (yy < -FONT_SIZE) break
        const alpha = (1 - k / d.len) * 0.22
        ctx.fillStyle = "rgba(245,245,245," + alpha + ")"
        const c = CHARS[(Math.random() * CHARS.length) | 0]
        ctx.fillText(c, x, yy)
      }
      d.y += FONT_SIZE * d.speed * 0.55
      if (d.y > h + d.len * FONT_SIZE) {
        d.y = -Math.random() * h * 0.5
        d.speed = 0.4 + Math.random() * 1.0
        d.len = 8 + Math.floor(Math.random() * 18)
      }
    }
  }

  withLifecycle(canvas, { resize, tick })
}

const bootedCanvases = new WeakSet()

function bootAuthCanvases() {
  const organic = document.getElementById("auth-canvas-organic")
  if (organic && !bootedCanvases.has(organic)) {
    bootedCanvases.add(organic)
    startOrganic(organic)
  }
  const matrix = document.getElementById("auth-canvas-matrix")
  if (matrix && !bootedCanvases.has(matrix)) {
    bootedCanvases.add(matrix)
    startMatrix(matrix)
  }
}

new MutationObserver(bootAuthCanvases).observe(document.documentElement, {
  childList: true,
  subtree: true,
})
bootAuthCanvases()
