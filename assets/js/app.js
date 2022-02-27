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

// Close chat window
window.addEventListener("keydown", event => {
  if (event.key == "Escape" && $("body").hasClass("right-bar-enabled")){
    $("body").toggleClass("right-bar-enabled");
  }
})

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: {_csrf_token: csrfToken}});
liveSocket.connect();

window.jQuery = $;
window.$ = $;
window.liveSocket = liveSocket;

// runs every time there is a LiveView update
$(document).on('phx:update', event => {
  initTooltips();

  initToasts();

  setChatSidebarHeight();
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
    inertia: true
  })
}

function initToasts(){
  $('.toast').toast();
}

function setChatSidebarHeight(){
  const wHeight = $(window).height();
  const bar = currentBar();
  const barHeight = bar && bar.offsetHeight || 0;
  const result = wHeight - barHeight;

  $('#chat').css("height", result);
  const container = $("#chat .messages-container");
  container[0] && container.css("height", result - 165);
  container[0] && container.scrollTop(container[0].scrollHeight);
}

function currentBar() {
  const element = document.getElementById("hero-bar");
  if (element){
    return element;
  }else{
    return document.getElementById("battle-bar");
  }
}
