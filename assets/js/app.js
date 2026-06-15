import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const Hooks = {
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
        if (!blockId) return
        const url =
          window.location.origin +
          window.location.pathname +
          window.location.search +
          "#" + blockId
        try { await navigator.clipboard.writeText(url) } catch (_) {}
        history.replaceState(null, "", "#" + blockId)
        const target = document.getElementById(blockId)
        if (target) {
          target.scrollIntoView({ behavior: "smooth", block: "start" })
          target.classList.remove("blk-target-flash")
          // force reflow so re-adding the class restarts the animation
          void target.offsetWidth
          target.classList.add("blk-target-flash")
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
