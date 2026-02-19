// V2 Asset Pipeline - BrowserMOBA
// CSS is built separately by Tailwind, not bundled via esbuild

import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

// V2 hooks - vanilla JS only, no jQuery
let Hooks = {}

// Tooltip hook — shows/hides game tooltip on hover
Hooks.Tooltip = {
  mounted() {
    const tooltip = this.el.querySelector("[data-tooltip-content]")
    if (!tooltip) return

    this.el.addEventListener("mouseenter", () => {
      tooltip.classList.add("visible")
    })
    this.el.addEventListener("mouseleave", () => {
      tooltip.classList.remove("visible")
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Connect if there are any LiveViews on the page
liveSocket.connect()

// Expose liveSocket on window for debug logs in dev:
//   >> liveSocket.enableDebug()
//   >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket
