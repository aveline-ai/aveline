import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()

// Expose for debugging in the browser console: window.liveSocket.enableDebug()
window.liveSocket = liveSocket
