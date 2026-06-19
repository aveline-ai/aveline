import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const Hooks = {
  // Toggle the workspace sidebar between expanded and collapsed. Source
  // of truth is `html.sidebar-collapsed` (set early by an inline script
  // in root.html.heex so there's no flash on load). User preference
  // lives in localStorage; viewport width drives the default when no
  // preference is set.
  SidebarCollapse: {
    mounted() {
      const root = document.documentElement
      const KEY = "aveline:sidebarCollapsed"

      const setCollapsed = (val, persist) => {
        root.classList.toggle("sidebar-collapsed", val)
        if (persist) localStorage.setItem(KEY, val ? "1" : "0")
      }

      // Initial sync in case localStorage changed between page loads.
      const pref = localStorage.getItem(KEY)
      if (pref === "1") setCollapsed(true, false)
      else if (pref === "0") setCollapsed(false, false)
      else setCollapsed(window.innerWidth < 1024, false)

      const btn = this.el.querySelector("[data-sidebar-toggle]")
      if (btn) {
        this.onToggle = (e) => {
          e.preventDefault()
          setCollapsed(!root.classList.contains("sidebar-collapsed"), true)
        }
        btn.addEventListener("click", this.onToggle)
      }

      // When the user hasn't set a preference, follow the viewport so
      // resizing across the breakpoint feels right.
      this.onResize = () => {
        if (localStorage.getItem(KEY) === null) {
          setCollapsed(window.innerWidth < 1024, false)
        }
      }
      window.addEventListener("resize", this.onResize)
    },
    destroyed() {
      window.removeEventListener("resize", this.onResize)
    },
  },


  // Click on the per-block anchor (¶ icon) next to a heading/paragraph/etc.
  // Copies the deep link to clipboard, updates the URL hash so the browser
  // remembers it, smooth-scrolls to the target, and flashes the block.
  // The hash already round-trips through `/d/:slug` and `/d/:slug/v/:N` —
  // so the link respects whichever version the reader is currently on.
  CopyBlockLink: {
    mounted() {
      this.el.addEventListener("click", async (e) => {
        e.preventDefault()
        const blockId = this.el.dataset.blockId
        const base =
          window.location.origin +
          window.location.pathname +
          window.location.search
        // No block id = title-level anchor: copy the doc URL itself.
        const url = blockId ? base + "#" + blockId : base
        try { await navigator.clipboard.writeText(url) } catch (_) {}
        if (blockId) {
          history.replaceState(null, "", "#" + blockId)
          const target = document.getElementById(blockId)
          if (target) {
            target.scrollIntoView({ behavior: "smooth", block: "start" })
            target.classList.remove("blk-target-flash")
            void target.offsetWidth
            target.classList.add("blk-target-flash")
          }
        }
        this.el.classList.add("copied")
        clearTimeout(this._t)
        this._t = setTimeout(() => this.el.classList.remove("copied"), 1200)
      })
    },
  },

  // Syntax-highlight a <pre><code> via Prism (loaded globally in root.html.heex).
  // `phx-update="ignore"` on the <pre> keeps LV from clobbering Prism's
  // injected DOM after the initial render.
  HighlightCode: {
    mounted() {
      const code = this.el.querySelector("code")
      if (code && window.Prism) {
        window.Prism.highlightElement(code)
      }
    },
  },

  // Auth-page split background: warm parchment + matrix cascade.
  // Both hooks size off their parent .auth-pane element, respect
  // prefers-reduced-motion, and pause when the tab isn't visible.

  OrganicCanvas: {
    mounted() {
      const canvas = this.el
      const ctx = canvas.getContext("2d")
      const DPR = Math.min(window.devicePixelRatio || 1, 2)
      let w = 0, h = 0, t = 0, motes = [], raf = 0

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
        raf = requestAnimationFrame(tick)
      }

      const start = () => { if (!raf) raf = requestAnimationFrame(tick) }
      const stop = () => { if (raf) cancelAnimationFrame(raf); raf = 0 }
      const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
      const obey = () => { stop(); if (!reduced.matches) start() }

      this._onResize = resize
      this._onVis = () => { if (document.hidden) stop(); else obey() }
      window.addEventListener("resize", this._onResize)
      document.addEventListener("visibilitychange", this._onVis)
      this._stop = stop

      resize()
      obey()
    },
    destroyed() {
      window.removeEventListener("resize", this._onResize)
      document.removeEventListener("visibilitychange", this._onVis)
      if (this._stop) this._stop()
    },
  },

  MatrixCanvas: {
    mounted() {
      const canvas = this.el
      const ctx = canvas.getContext("2d")
      const DPR = Math.min(window.devicePixelRatio || 1, 2)
      const FONT_SIZE = 14
      const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{}[]<>=/+-*?!#$%&"
      let w = 0, h = 0, cols = 0, drops = [], raf = 0

      const resize = () => {
        w = canvas.parentElement.clientWidth
        h = canvas.parentElement.clientHeight
        canvas.width = w * DPR; canvas.height = h * DPR
        canvas.style.width = w + "px"; canvas.style.height = h + "px"
        ctx.setTransform(DPR, 0, 0, DPR, 0, 0)
        cols = Math.ceil(w / FONT_SIZE)
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
        raf = requestAnimationFrame(tick)
      }

      const start = () => { if (!raf) raf = requestAnimationFrame(tick) }
      const stop = () => { if (raf) cancelAnimationFrame(raf); raf = 0 }
      const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
      const obey = () => { stop(); if (!reduced.matches) start() }

      this._onResize = resize
      this._onVis = () => { if (document.hidden) stop(); else obey() }
      window.addEventListener("resize", this._onResize)
      document.addEventListener("visibilitychange", this._onVis)
      this._stop = stop

      resize()
      obey()
    },
    destroyed() {
      window.removeEventListener("resize", this._onResize)
      document.removeEventListener("visibilitychange", this._onVis)
      if (this._stop) this._stop()
    },
  },

  // Focus an element as soon as it mounts. Use on inline composers that
  // are conditionally rendered — the HTML `autofocus` attribute fires
  // only on initial page load, not on subsequent LV patches.
  AutoFocus: {
    mounted() {
      // Defer one tick so any layout/transition completes first.
      requestAnimationFrame(() => this.el.focus())
    },
  },

  // Reset a form when the server pushes the configured event.
  //
  //   <form phx-hook="ResetOnEvent" data-reset-event="reset-form">
  //
  //   {:noreply, push_event(socket, "reset-form", %{id: "reply-form"})}
  ResetOnEvent: {
    mounted() {
      const evt = this.el.dataset.resetEvent || "reset-form"
      const id = this.el.id

      // Cmd+Enter / Ctrl+Enter submits from any field in the form.
      this.el.addEventListener("keydown", (e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
          e.preventDefault()
          this.el.requestSubmit()
        }
      })

      this.handleReset = (e) => {
        if (!e.detail || e.detail.id !== id) return
        this.el.reset()
        const focusable = this.el.querySelector("textarea, input")
        if (focusable) focusable.focus()
      }
      window.addEventListener(`phx:${evt}`, this.handleReset)
    },
    destroyed() {
      const evt = this.el.dataset.resetEvent || "reset-form"
      if (this.handleReset) {
        window.removeEventListener(`phx:${evt}`, this.handleReset)
      }
    },
  },

  // Auto-scroll a scrollable element to the bottom when its `data-count`
  // attribute grows (i.e. a new child was appended) AND the user is
  // already near the bottom. If they've scrolled up to read history,
  // don't yank them back.
  //
  //   <div phx-hook="ScrollOnAppend" data-count={length(@messages)}>
  ScrollOnAppend: {
    mounted() {
      this.lastCount = parseInt(this.el.dataset.count || "0", 10)
      this.scrollToBottom()
    },
    updated() {
      const count = parseInt(this.el.dataset.count || "0", 10)
      if (count > this.lastCount) {
        const distanceFromBottom =
          this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
        if (distanceFromBottom < 120) this.scrollToBottom()
      }
      this.lastCount = count
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    },
  },

  // Copies the value of `data-target` (CSS selector) to the clipboard
  // when this element is clicked. Works for inputs (reads .value) and
  // regular elements (reads .textContent). Dispatches `phx:token-copied`
  // so other elements (the Continue button, the unload guard) can react.
  CopyToken: {
    mounted() {
      this.el.addEventListener("click", async (e) => {
        e.preventDefault()
        const targetSel = this.el.dataset.target
        const target = document.querySelector(targetSel)
        if (!target) return
        const text =
          target.tagName === "INPUT" || target.tagName === "TEXTAREA"
            ? target.value.trim()
            : target.textContent.trim()
        try {
          await navigator.clipboard.writeText(text)
        } catch (err) {
          // fall through — selection-based copy fallback below
          try {
            const range = document.createRange()
            range.selectNodeContents(target)
            const sel = window.getSelection()
            sel.removeAllRanges()
            sel.addRange(range)
            document.execCommand("copy")
            sel.removeAllRanges()
          } catch (err2) {
            this.setLabel("Couldn't copy — select manually")
            return
          }
        }
        this.setLabel("Copied ✓")
        this.el.classList.add("copied")
        window.dispatchEvent(new CustomEvent("phx:token-copied"))
      })
    },
    // Some copy buttons have nested SVG + a .token-field-copy-label
    // <span>. Set the label without clobbering the icon.
    setLabel(text) {
      const labelEl = this.el.querySelector(".token-field-copy-label")
      if (labelEl) labelEl.textContent = text
      else this.el.textContent = text
    },
  },

  // Tracks whether a target element has been copied (via our Copy
  // button OR via native Ctrl/Cmd+C on the input) and flips the value
  // of a hidden input from "false" to "true" so the server can see it
  // in submitted form data. Does NOT block submission — the server
  // decides whether to error on the missing copy.
  //
  //   <form phx-hook="TrackCopy"
  //         data-target="#preview-token-value"
  //         data-flag="#copied-flag" />
  TrackCopy: {
    mounted() {
      const targetSel = this.el.dataset.target
      const target = targetSel ? document.querySelector(targetSel) : null
      const flagSel = this.el.dataset.flag
      const flag = flagSel ? document.querySelector(flagSel) : null

      const setCopied = () => {
        if (flag) flag.value = "true"
      }

      this.onCopied = setCopied
      window.addEventListener("phx:token-copied", setCopied)

      if (target) {
        this.onNativeCopy = setCopied
        target.addEventListener("copy", setCopied)
      }
    },
    destroyed() {
      if (this.onCopied) window.removeEventListener("phx:token-copied", this.onCopied)
    },
  },

  // Guards an unsaved-token page: warns on reload/close until a
  // `phx:token-copied` event fires; also enables the Continue button
  // once the token is copied.
  UnsavedTokenGuard: {
    mounted() {
      this.copied = false
      this.beforeUnload = (e) => {
        if (this.copied) return
        e.preventDefault()
        e.returnValue =
          "You haven't copied your API token yet. If you leave, you'll never see it again."
      }
      window.addEventListener("beforeunload", this.beforeUnload)

      this.onCopied = () => {
        this.copied = true
        const continueBtn = document.getElementById("continue-btn")
        if (continueBtn) continueBtn.disabled = false
      }
      window.addEventListener("phx:token-copied", this.onCopied)

      // Allow form submit (continue) to navigate without the unload prompt.
      const form = document.getElementById("continue-form")
      if (form) {
        form.addEventListener("submit", () => {
          this.copied = true
        })
      }
    },
    destroyed() {
      window.removeEventListener("beforeunload", this.beforeUnload)
      window.removeEventListener("phx:token-copied", this.onCopied)
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()

// If the page loaded with a #block hash, flash it once the LV is mounted.
function flashCurrentHash() {
  const id = window.location.hash.slice(1)
  if (!id) return
  const el = document.getElementById(id)
  if (!el) return
  el.classList.remove("blk-target-flash")
  void el.offsetWidth
  el.classList.add("blk-target-flash")
}
window.addEventListener("load", () => setTimeout(flashCurrentHash, 80))
window.addEventListener("phx:page-loading-stop", () => setTimeout(flashCurrentHash, 80))
window.addEventListener("hashchange", flashCurrentHash)

// Expose for debugging in the browser console: window.liveSocket.enableDebug()
window.liveSocket = liveSocket
