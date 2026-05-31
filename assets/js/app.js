import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const Hooks = {
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

  // Copies the textContent of `data-target` (CSS selector) to the
  // clipboard when this element is clicked. Dispatches `phx:token-copied`
  // so other elements (the Continue button, the unload guard) can react.
  CopyToken: {
    mounted() {
      this.el.addEventListener("click", async (e) => {
        e.preventDefault()
        const targetSel = this.el.dataset.target
        const target = document.querySelector(targetSel)
        if (!target) return
        const text = target.textContent.trim()
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
            this.el.textContent = "Couldn't copy — select the token above manually"
            return
          }
        }
        this.el.textContent = "Copied ✓"
        this.el.classList.add("copied")
        window.dispatchEvent(new CustomEvent("phx:token-copied"))
      })
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

// Expose for debugging in the browser console: window.liveSocket.enableDebug()
window.liveSocket = liveSocket
