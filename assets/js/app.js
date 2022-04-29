// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import css from "../css/app.scss"

import "phoenix_html"
import 'bootstrap';
import $ from 'jquery';
import tippy from 'tippy.js';
import topbar from "topbar";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import mobileCheck from "./mobile_check";
import Hooks from "./hooks";

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
let topBarScheduled = undefined;

window.addEventListener("phx:page-loading-start", () => {
  if(!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 200);
  }
});

window.addEventListener("phx:page-loading-stop", () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: {_csrf_token: csrfToken}});
liveSocket.connect();

window.jQuery = $;
window.$ = $;
window.liveSocket = liveSocket;

// runs every time there is a LiveView update
$(document).on('phx:update', event => {
  initTooltips();

  scrollChat();
});

function initTooltips(){
  tippy('[data-toggle="tooltip"]', {
    onShow(instance) {
      let showMobile = $(instance.reference).hasClass("tooltip-mobile");
      return showMobile || !mobileCheck(); // cancels tooltip if on mobile
    },
    content(reference) {
      const title = reference.getAttribute('title');
      reference.removeAttribute('title');
      return title;
    },
    arrow: true,
    allowHTML: true,
    inertia: true,
    hideOnClick: "toggle"
  })
}

function scrollChat(){
  const container = $(".inbox-widget");
  container[0] && container.scrollTop(container[0].scrollHeight);
}
