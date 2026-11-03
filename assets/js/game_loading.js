// Read only what is already rendered. Never fetch an opponent or derive asset URLs.
export function loadingTarget(control, to, root = document) {
  const text = (node, selector) => (selector ? node?.querySelector(selector) : node)?.textContent?.trim().replace(/\s+/g, ' ') || '';
  const image = (node, selector = 'img') => node?.querySelector(selector)?.getAttribute('src') || '';
  const art = node => {
    if (!node) return '';
    const background = window.getComputedStyle(node).backgroundImage;
    return background?.match(/url\(["']?(.*?)["']?\)/)?.[1] || '';
  };
  const portrait = (node, name, subtitle, selector) => ({
    name, subtitle, image: image(node, selector), art: art(node)
  });
  const event = control?.getAttribute('phx-click') || control?.dataset?.invokeAction;
  let path;
  try { path = new URL(to || window.location.href, window.location.href).pathname; }
  catch (_) { return null; }
  const samePage = path === window.location.pathname;

  if (event === 'battle') {
    const card = control.closest('.training-target');
    if (card) return {name: text(card, '.target-name'), subtitle: `Level ${text(card, '.target-level-value')} · Training battle`, art: art(card)};
  }
  if (event === 'league') {
    const boss = control.closest('#roshan-challenge');
    if (boss) return {name: text(boss, '#roshan-title'), subtitle: text(boss, '.roshan-attempt'), art: art(boss.querySelector('.roshan-portrait'))};
    const ascent = control.closest('#training-ascent');
    if (ascent) return portrait(ascent, text(ascent, '.is-next .ascent-rank-name'), 'League challenge', '.is-next img');
  }
  if (event === 'challenge') {
    const row = control.closest('li');
    return portrait(row, text(row, '.arena-live-opponent-identity strong'), 'Live 1v1', '.arena-live-opponent-identity img');
  }
  if (event === 'accept') {
    const challenger = root.querySelector('.duel-challenge-opponent');
    return portrait(challenger, text(challenger, 'strong'), 'Live 1v1');
  }
  if (event === 'rematch') {
    const opponent = root.querySelector('.duel-contestant-opponent');
    return portrait(opponent, text(opponent, 'a'), 'Live 1v1 · Rematch');
  }
  if (event === 'create') {
    const selected = root.querySelector('.invoke-avatar-art');
    return {name: control.dataset.heroName || text(control).replace(/\s*→$/, ''), subtitle: 'Your next hero', art: control.dataset.heroArt || art(selected)};
  }
  if (event === 'continue') {
    const card = control.closest('.hero-card');
    if (card) return {name: text(card, '.hero-card-name, .hero-name'), subtitle: 'Continue training', art: art(card)};
  }
  if (event === 'matchmaking' || (event === 'start' && control.closest('#match-hud'))) {
    return {name: '5v5', subtitle: event === 'start' ? 'Entering the Arena' : 'Finding your match'};
  }
  if (event === 'season-duel') return {name: '1v1', subtitle: 'Finding your opponent'};
  if (event && !to) return null; // Local actions must not inherit the current page's identity.

  if (/^\/hero\/\d+\/?$/.test(path)) {
    const card = control?.closest('.hero-card, .profile-featured, .profile-debut-hero') || control ||
      (samePage && root.querySelector('#hero-detail-card'));
    if (card) {
      const name = text(card, '.hero-card-name, .hero-name, #hero-detail-name, strong');
      const detail = text(card, '.hero-card-meta, .hero-detail-avatar-name, small, .profile-featured-heading span[data-toggle]');
      const header = root.querySelector('#profile-cinematic');
      const heroArt = art(card) || image(card, '.card-body > img, .profile-debut-art') || (header && card.matches('.profile-featured') ?
        window.getComputedStyle(header).getPropertyValue('--profile-scene').match(/url\(["']?(.*?)["']?\)/)?.[1] : '');
      return {name: name || card.querySelector('img')?.alt, subtitle: detail || 'Hero profile',
        image: heroArt ? '' : image(card, 'img:not([src*="/league/"]):not([src*="/pve/"])'), art: heroArt};
    }
  }
  if (/^\/player\/\d+\/?$/.test(path)) {
    if (control) {
      if (control.closest('#game-sidebar, #topnav')) return null;
      return {name: text(control, 'strong, .profile-ranked-name') || text(control).replace(text(control, 'small'), '').trim(), simple: true};
    }
    const header = samePage && root.querySelector('#profile-cinematic');
    if (header) return {name: text(header, 'h1'), simple: true};
  }
  if (/^\/(matches|arena)\/\d+\/?$/.test(path)) {
    const row = control?.closest('tr');
    const player = row?.querySelector('a[href^="/player/"]');
    if (player) return portrait(row, text(player), path.startsWith('/matches/') ? '5v5 match' : '1v1 duel');
    const challenger = root.querySelector('.duel-challenge-opponent');
    if (challenger && path.startsWith('/arena/')) return portrait(challenger, text(challenger, 'strong'), 'Live 1v1');
  }
  if (/^\/battles\/\d+\/?$/.test(path)) {
    const row = control?.closest('.match-summary-row, .duel-round-battle, .match-battle');
    if (row) {
      const heroes = [...row.querySelectorAll('.match-summary-hero img, .duel-survivor img, .match-battle-hero img')];
      const names = heroes.map(hero => hero.alt || text(hero.parentElement, 'strong')).filter(Boolean);
      if (heroes.length) return {name: names.join(' vs ') || 'Battle replay', subtitle: 'Battle replay', image: heroes[0]?.getAttribute('src'), opponent: heroes[1]?.getAttribute('src')};
    }
    const round = control?.closest('.duel-round') || root.querySelector('.duel-round:has(.duel-round-battle[data-finished=false])');
    const picks = round && [...round.querySelectorAll('.hero-card')];
    if (picks?.length === 2) return {name: picks.map(pick => text(pick, '.hero-card-name')).join(' vs '), subtitle: '1v1 battle',
      image: art(picks[0]), opponent: art(picks[1])};
    const duel = root.querySelector('#duel-banner');
    if (duel) return {name: [...duel.querySelectorAll('.duel-contestant a')].map(node => text(node)).join(' vs '), subtitle: '1v1 battle',
      image: image(duel, '.duel-contestant img'), opponent: image(duel, '.duel-contestant-opponent img')};
  }
  if (path === '/training') {
    // The scene includes ownership even when the opponent occupies the left side.
    const scene = root.querySelector('#combat-stage');
    if (scene) {
      try {
        const unit = JSON.parse(scene.dataset.scene).units.find(unit => unit.you);
        if (unit) return {name: unit.avatar, subtitle: 'Continue training', image: unit.portrait, art: unit.art};
      } catch (_) { /* A missing scene must not interrupt navigation. */ }
    }
    const hud = root.querySelector('#hero-bar');
    if (hud) return portrait(hud, text(hud, '.hero-name'), 'Training', 'img.avatar');
  }
  return null;
}

export function initGameLoading() {
  const screen = document.getElementById('game-loading-screen');
  if (!screen) return;

  const fill = document.getElementById('game-loading-fill');
  const progress = document.getElementById('game-loading-progress');
  const icon = document.getElementById('game-loading-icon');
  const title = document.getElementById('game-loading-title');
  const subtitle = document.getElementById('game-loading-subtitle');
  const backdrop = document.getElementById('game-loading-art');
  const opponent = document.getElementById('game-loading-opponent');
  const active = new Set();
  let pendingTarget;
  let currentTarget;
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
    pendingTarget = null;
    currentTarget = null;
  }

  function present(target, to) {
    const fallback = `/images/navigation/${destinationIcon(to)}.webp`;
    icon.onerror = () => { icon.onerror = null; icon.src = fallback; };
    icon.src = target?.image || target?.art || fallback;
    screen.dataset.target = target?.name ? 'true' : 'false';
    screen.dataset.portrait = target?.image || target?.art ? 'true' : 'false';
    screen.dataset.simple = String(target?.simple === true);
    if (title) { title.textContent = target?.name || ''; title.hidden = !target?.name; }
    if (subtitle) { subtitle.textContent = target?.subtitle || ''; subtitle.hidden = !target?.subtitle; }
    if (backdrop) {
      backdrop.hidden = !target?.art;
      backdrop.onerror = () => { backdrop.hidden = true; };
      if (target?.art) backdrop.src = target.art;
      else backdrop.removeAttribute('src');
    }
    if (opponent) {
      opponent.hidden = !target?.opponent;
      opponent.onerror = () => { opponent.hidden = true; };
      if (target?.opponent) opponent.src = target.opponent;
      else opponent.removeAttribute('src');
    }
    screen.setAttribute('aria-label', target?.name ? `Loading ${target.name}` : 'Loading BrowserMOBA');
  }

  function start(detail) {
    if (detail.kind === 'redirect' || detail.kind === 'patch') active.clear();
    active.add(detail);
    clearTimeout(completion);
    clearInterval(trickle);
    amount = 8;
    if (detail.kind !== 'initial' || !currentTarget) {
      let path;
      try { path = new URL(detail.to || window.location.href, window.location.href).pathname; } catch (_) {}
      const pending = pendingTarget && Date.now() - pendingTarget.at < 10000 && pendingTarget.accepts(path);
      currentTarget = pending ? pendingTarget.target : loadingTarget(null, detail.to);
      present(currentTarget, detail.to);
    }
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

  // Capture before LiveView/Loading hooks replace button text or stop propagation.
  // Remember context, but show the overlay only when navigation actually starts.
  document.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    pendingTarget = null;
    const control = event.target.closest('a[href], button[phx-click], button[data-invoke-action="create"]');
    if (!control || control.disabled || control.getAttribute('aria-disabled') === 'true' || control.target ||
        ['download', 'data-method'].some(attribute => control.hasAttribute(attribute))) return;
    let url;
    if (control.hasAttribute('href')) {
      try { url = new URL(control.href, window.location.href); } catch (_) { return; }
      if (url.origin !== window.location.origin || !['http:', 'https:'].includes(url.protocol)) return;
    }
    const target = loadingTarget(control, url?.href);
    if (!target?.name) return;
    const action = control.getAttribute('phx-click') || control.dataset?.invokeAction;
    pendingTarget = {target, at: Date.now(), accepts: path => url ? path === url.pathname :
      (['create', 'continue'].includes(action) ? path === '/training' : /^\/(battles|matches|arena)\/\d+\/?$/.test(path))};
  }, true);

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
