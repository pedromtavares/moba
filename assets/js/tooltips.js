import tippy from 'tippy.js';
import mobileCheck from './mobile_check';
import {isGameTooltip, tooltipContent} from './game_feedback';

const instances = new Set();
const titles = new WeakMap();
let observer;

function cleanupTooltips() {
  instances.forEach(instance => {
    const reference = instance.reference;
    if (!reference.isConnected || !reference.matches('[data-toggle="tooltip"]') ||
        (instance.state.isVisible && reference.getClientRects().length === 0)) {
      instance.destroy();
    }
  });
}

export function hideTooltips() {
  instances.forEach(instance => {
    instance.clearDelayTimeouts();
    instance.hide();
  });
}

export function initTooltips() {
  if (!observer) {
    observer = new MutationObserver(records => {
      if (records.some(record => record.removedNodes.length > 0)) cleanupTooltips();
    });
    observer.observe(document.body, {childList: true, subtree: true});
  }

  cleanupTooltips();
  const targets = Array.from(document.querySelectorAll('[data-toggle="tooltip"]')).filter(reference => {
    // Tooltip markup can itself contain stat badges; those are not new anchors.
    if (reference.closest('[data-tippy-root]')) return false;
    if (!reference._tippy) return true;

    const title = reference.getAttribute('title');
    if (title !== null) {
      titles.set(reference, title);
      reference._tippy.setContent(tooltipContent(reference, title));
      reference.removeAttribute('title');
    }
    return false;
  });

  tippy(targets, {
    onShow(instance) {
      if (!instance.reference.isConnected || instance.reference.getClientRects().length === 0) return false;
      if (isGameTooltip(instance.reference)) return true;
      return instance.reference.classList.contains('tooltip-mobile') || !mobileCheck();
    },
    content(reference) {
      const title = reference.getAttribute('title') ?? titles.get(reference);
      if (title !== undefined && title !== null) titles.set(reference, title);
      reference.removeAttribute('title');
      if (isGameTooltip(reference) && reference.matches('img') && !reference.hasAttribute('tabindex')) {
        reference.setAttribute('tabindex', '0');
      }
      return tooltipContent(reference, title);
    },
    onCreate(instance) {
      instances.add(instance);
      if (isGameTooltip(instance.reference)) {
        const artwork = instance.reference.hasAttribute('data-tooltip-artwork');
        instance.setProps({theme: artwork ? 'game game-artwork' : 'game', maxWidth: artwork ? 'none' : 420});
      }
    },
    onDestroy(instance) {
      instances.delete(instance);
    },
    arrow: true,
    allowHTML: true,
    inertia: true
  });
}
