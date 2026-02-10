// V2 Asset Pipeline - BrowserMOBA
// Imports CSS so esbuild bundles it alongside JS
import "../css/app.css"

// Phoenix LiveView setup
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

// V2 hooks - vanilla JS only, no jQuery
let Hooks = {}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Connect if there are any LiveViews on the page
liveSocket.connect()

// Expose liveSocket on window for debug logs in dev:
//   >> liveSocket.enableDebug()
//   >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket
