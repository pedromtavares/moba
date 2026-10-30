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
import {initGameConfirmations, isGameTooltip, tooltipContent} from "./game_feedback";
import {initAnalytics} from "./analytics";

initGameConfirmations();
initAnalytics();

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

document.addEventListener('DOMContentLoaded', () => {
  document.addEventListener('keydown', (event) => {
    const skillKeys = ['q', 'w', 'e', 'r', 'f'];
    const itemKeys = ['1', '2', '3', '4', '5', '6'];

    const key = event.key.toLowerCase();
    
    if (skillKeys.includes(key)) {
      const index = skillKeys.indexOf(key);
      const skillElement = document.querySelector(`.skill-img[data-index="${index}"].can-use`);
      if (skillElement) {
        skillElement.click();
        document.getElementById('attack-button').click();
      }
    } else if (itemKeys.includes(key)) {
      const index = itemKeys.indexOf(key);
      const itemElement = document.querySelector(`.item-img[data-index="${index}"].can-use`);
      if (itemElement) {
        itemElement.click();
      }
    }
  });
});

// runs every time there is a LiveView update
$(document).on('phx:update', event => {
  initTooltips();

  scrollChat();
});

function initTooltips(){
  const targets = Array.from(document.querySelectorAll('[data-toggle="tooltip"]')).filter(reference => {
    if (!reference._tippy) return true;

    const title = reference.getAttribute('title');
    if (title !== null) {
      reference._tippy.setContent(tooltipContent(reference, title));
      reference.removeAttribute('title');
    }
    return false;
  });

  tippy(targets, {
    onShow(instance) {
      if (isGameTooltip(instance.reference)) return true;
      let showMobile = $(instance.reference).hasClass("tooltip-mobile");
      return showMobile || !mobileCheck(); // cancels tooltip if on mobile
    },
    content(reference) {
      const title = reference.getAttribute('title');
      reference.removeAttribute('title');
      if (isGameTooltip(reference) && reference.matches('img') && !reference.hasAttribute('tabindex')) {
        reference.setAttribute('tabindex', '0');
      }
      return tooltipContent(reference, title);
    },
    onCreate(instance) {
      if (isGameTooltip(instance.reference)) {
        const artwork = instance.reference.hasAttribute('data-tooltip-artwork');
        instance.setProps({theme: artwork ? 'game game-artwork' : 'game', maxWidth: artwork ? 'none' : 420});
      }
    },
    arrow: true,
    allowHTML: true,
    inertia: true
  })
}

function scrollChat(){
  const container = $(".inbox-widget");
  container[0] && container.scrollTop(container[0].scrollHeight);
}
