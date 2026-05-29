import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const Hooks = {
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
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()

// Expose for debugging in the browser console: window.liveSocket.enableDebug()
window.liveSocket = liveSocket
