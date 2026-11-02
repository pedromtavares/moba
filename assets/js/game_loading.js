export function initGameLoading() {
  const screen = document.getElementById('game-loading-screen');
  if (!screen) return;

  const fill = document.getElementById('game-loading-fill');
  const progress = document.getElementById('game-loading-progress');
  const icon = document.getElementById('game-loading-icon');
  const active = new Set();
  const lockedContent = new Map();
  let trickle;
  let completion;
  let amount = 0;

  function destinationIcon(to) {
    let section;
    try { section = new URL(to || window.location.href, window.location.href).pathname.split('/')[1]; }
    catch (_) { return 'profile'; }
    return {
      base: 'base', training: 'training', invoke: 'training', battles: 'training',
      arena: 'arena', matches: 'arena', tavern: 'tavern', community: 'community',
      library: 'manual', admin: 'admin'
    }[section] || 'profile';
  }

  function content() {
    return document.getElementById('game-content') || document.getElementById('main-wrapper');
  }

  function position() {
    const sidebar = document.getElementById('game-sidebar');
    const topnav = document.getElementById('topnav');
    const left = sidebar?.getClientRects().length ? sidebar.getBoundingClientRect().right : 0;
    const top = topnav?.getClientRects().length ? Math.max(0, topnav.getBoundingClientRect().bottom) : 0;
    screen.style.setProperty('--loading-left', `${left}px`);
    screen.style.setProperty('--loading-top', `${top}px`);
  }

  function busy(value) {
    if (!value) {
      // Navigation can replace #game-content or introduce it inside #main-wrapper.
      // Release the containers we locked, rather than looking up the new layout.
      lockedContent.forEach((previous, target) => {
        target.inert = previous.inert;
        if (previous.busy === null) target.removeAttribute('aria-busy');
        else target.setAttribute('aria-busy', previous.busy);
      });
      lockedContent.clear();
      return;
    }

    const target = content();
    if (target) {
      if (!lockedContent.has(target)) {
        lockedContent.set(target, {inert: target.inert, busy: target.getAttribute('aria-busy')});
      }
      target.inert = true;
      target.setAttribute('aria-busy', 'true');
    }
  }

  function reset() {
    clearInterval(trickle);
    clearTimeout(completion);
    active.clear();
    screen.hidden = true;
    screen.dataset.state = 'idle';
    busy(false);
  }

  function start(detail) {
    if (detail.kind === 'redirect' || detail.kind === 'patch') active.clear();
    active.add(detail);
    clearTimeout(completion);
    clearInterval(trickle);
    amount = 8;
    icon.src = `/images/navigation/${destinationIcon(detail.to)}.webp`;
    fill.style.width = `${amount}%`;
    progress.removeAttribute('aria-valuenow'); // Navigation has no measurable byte total.
    position();
    busy(true);
    screen.hidden = false;
    screen.dataset.state = 'loading';
    trickle = setInterval(() => {
      amount = Math.min(90, amount + (90 - amount) * 0.12);
      fill.style.width = `${amount}%`;
    }, 220);
  }

  window.addEventListener('phx:page-loading-start', ({detail}) => {
    if (detail.kind === 'error') return reset();
    if (['initial', 'redirect', 'patch'].includes(detail.kind)) start(detail);
  });

  window.addEventListener('phx:page-loading-stop', ({detail}) => {
    if (!active.delete(detail) || active.size) return;
    clearInterval(trickle);
    position();
    busy(false);
    fill.style.width = '100%';
    progress.setAttribute('aria-valuenow', '100');
    screen.dataset.state = 'complete';
    completion = setTimeout(reset, 320);
  });

  // Full document links (such as settings) also show the outgoing transition.
  document.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest('a[href]');
    if (!link || link.target || ['download', 'data-method', 'phx-click', 'data-phx-link'].some(attribute => link.hasAttribute(attribute))) return;
    let to;
    try { to = new URL(link.href, window.location.href); } catch (_) { return; }
    if (to.origin !== window.location.origin || !['http:', 'https:'].includes(to.protocol) ||
        (to.pathname === window.location.pathname && to.search === window.location.search)) return;
    start({kind: 'redirect', to: to.href});
  });

  window.addEventListener('resize', () => { if (!screen.hidden) position(); });
  window.addEventListener('pageshow', event => { if (event.persisted) reset(); });
}
