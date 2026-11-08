// Fullscreen the document, which survives LiveView swaps of the game content.
// Browsers require a user gesture, so launch controls request it before the
// server creates the battle. Direct visits wait for the first interaction.
export function initGameFullscreen() {
  let entering = false;
  let pendingEntry = false;
  let currentBattle = null;
  let escapeLock = null;

  function modalCloseButton() {
    return Array.from(document.querySelectorAll('[data-close-on-escape]'))
      .reverse().find(button => button.getClientRects().length);
  }

  function updateEscapeLock() {
    const keyboard = navigator.keyboard;
    if (!keyboard?.lock || !keyboard.unlock) return;

    if (!document.fullscreenElement || !modalCloseButton()) {
      if (escapeLock) {
        escapeLock = null;
        keyboard.unlock();
      }
      return;
    }

    if (escapeLock) return;
    const request = escapeLock = {};
    try {
      Promise.resolve(keyboard.lock(['Escape'])).then(() => {
        // A modal may close before the browser finishes granting the lock.
        if (escapeLock !== request && !escapeLock) keyboard.unlock();
      }, () => {});
    } catch (_) {
      // Fullscreen keyboard handling still works when the browser supports it directly.
    }
  }

  function battlePath(href) {
    try {
      const url = new URL(href, window.location.href);
      return url.origin === window.location.origin && /^\/(battles|matches|arena)\/\d+\/?$/.test(url.pathname)
        ? url.pathname : null;
    } catch (_) {
      return null;
    }
  }

  function enter() {
    pendingEntry = false;
    if (entering || document.fullscreenElement || document.fullscreenEnabled === false ||
        !document.documentElement.requestFullscreen) return;

    entering = true;
    try {
      Promise.resolve(document.documentElement.requestFullscreen({keyboardLock: 'browser'}))
        .catch(() => {}) // Unsupported/denied fullscreen must never block play.
        .finally(() => { entering = false; });
    } catch (_) {
      entering = false;
    }
  }

  function pageChanged() {
    const nextBattle = battlePath(window.location.href);
    if (nextBattle !== currentBattle) {
      currentBattle = nextBattle;
      pendingEntry = !!nextBattle && !document.fullscreenElement;
      if (pendingEntry && navigator.userActivation?.isActive) enter();
    }
  }

  document.addEventListener('click', event => {
    if (event.isTrusted === false || event.defaultPrevented || event.button !== 0 ||
        event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;

    const control = event.target.closest('[data-game-fullscreen], a[href]');
    const launch = control && !control.disabled && control.getAttribute('aria-disabled') !== 'true' &&
      (control.hasAttribute('data-game-fullscreen') ||
        (!control.hasAttribute('download') && !control.target && battlePath(control.href)));
    const interaction = pendingEntry && event.target.closest('#battle-page, #match-hud, #duel-page') &&
      !event.target.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"])');
    if (launch || interaction) enter();
  }, true);

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      const close = modalCloseButton();
      if (close) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (!event.repeat && !close.hasAttribute('data-phx-ref-loading')) close.click();
      }
      return;
    }
    if (!pendingEntry || event.isTrusted === false || event.defaultPrevented || event.repeat ||
        event.isComposing || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey ||
        event.target.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"])')) return;
    if (event.code === 'Space' || ['q', 'w', 'e', 'r', 'f', '1', '2', '3', '4', '5', '6', 'Enter'].includes(event.key)) enter();
  }, true);

  window.addEventListener('phx:page-loading-stop', pageChanged);
  document.addEventListener('phx:update', updateEscapeLock);
  document.addEventListener('team:hero-switched', updateEscapeLock);
  document.addEventListener('fullscreenchange', () => {
    if (document.fullscreenElement) pendingEntry = false;
    updateEscapeLock();
  });
  pageChanged();
  updateEscapeLock();
  return enter;
}
