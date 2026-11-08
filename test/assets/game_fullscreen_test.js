const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/game_fullscreen.js', 'utf8')
  .replace('export function initGameFullscreen()', 'function initGameFullscreen()') + '\ninitGameFullscreen();';

function environment(path = '/training', options = {}) {
  const listeners = {};
  const modals = [];
  const document = {
    fullscreenElement: options.fullscreen ? {tagName: 'HTML'} : null,
    fullscreenEnabled: true,
    addEventListener: (event, listener) => { listeners[event] = listener; },
    querySelectorAll: () => modals
  };
  let requests = 0;
  let fullscreenOptions;
  document.documentElement = {
    requestFullscreen(options) {
      fullscreenOptions = options;
      requests++;
      if (options.throw) throw new Error('Not supported');
      if (options.deny) return Promise.reject(new Error('Denied'));
      document.fullscreenElement = document.documentElement;
      listeners.fullscreenchange?.();
      return Promise.resolve();
    }
  };
  const location = {href: `https://browsermoba.com${path}`, origin: 'https://browsermoba.com'};
  const activation = {isActive: false};
  vm.runInNewContext(source, {
    URL, Promise, document, navigator: {userActivation: activation, keyboard: options.keyboard},
    window: {location, addEventListener: (event, listener) => { listeners[event] = listener; }}
  });

  function click(control = null, options = {}) {
    const event = {
      isTrusted: true, button: 0, defaultPrevented: false,
      target: {closest: selector => {
        if (selector === '[data-game-fullscreen], a[href]') return control;
        if (selector === '#battle-page, #match-hud, #duel-page') return options.inBattle;
        return options.editable;
      }}, ...options
    };
    listeners.click(event);
    return event;
  }
  function control({href, launch = false, ...options} = {}) {
    return {
      href, disabled: false, target: '', getAttribute: () => null,
      hasAttribute: name => name === 'data-game-fullscreen' && launch,
      ...options
    };
  }
  function navigate(path) {
    location.href = `https://browsermoba.com${path}`;
    listeners['phx:page-loading-stop']();
  }
  function escape(repeat = false) {
    const event = {
      key: 'Escape', repeat,
      preventDefault() { this.defaultPrevented = true; },
      stopImmediatePropagation() { this.stopped = true; }
    };
    listeners.keydown(event);
    return event;
  }
  return {document, listeners, activation, click, control, navigate, escape, modals,
    requests: () => requests, fullscreenOptions: () => fullscreenOptions};
}

test('battle launch controls synchronously fullscreen the persistent document root', () => {
  const env = environment();
  env.click(env.control({launch: true}));
  assert.equal(env.requests(), 1);
  assert.equal(env.document.fullscreenElement, env.document.documentElement);
  assert.equal(env.fullscreenOptions().keyboardLock, 'browser');
});

test('training, duel and 5v5 links including resumes and reviews enter fullscreen', () => {
  for (const path of ['/battles/12', '/matches/34', '/arena/56', '/arena/56?round=2']) {
    const env = environment();
    env.click(env.control({href: `https://browsermoba.com${path}`}));
    assert.equal(env.requests(), 1, path);
  }
});

test('already fullscreen stays fullscreen through game navigation without another request', () => {
  const env = environment('/battles/12', {fullscreen: true});
  const root = env.document.fullscreenElement;
  for (const path of ['/training', '/base', '/arena', '/arena/56', '/matches/34', '/player/1', '/community']) {
    env.navigate(path);
    env.click(env.control({href: `https://browsermoba.com${path}`}));
    assert.equal(env.document.fullscreenElement, root);
  }
  assert.equal(env.requests(), 0);
});

test('Escape closes only the visible modal and releases the fullscreen lock after the LiveView update', async () => {
  const locks = [];
  let unlocks = 0;
  const keyboard = {
    lock(keys) { locks.push(Array.from(keys)); return Promise.resolve(); },
    unlock() { unlocks++; }
  };
  const env = environment('/training', {fullscreen: true, keyboard});
  const closeButton = () => ({
    visible: false, closing: false, clicks: 0,
    getClientRects() { return this.visible ? [{}] : []; },
    hasAttribute(name) { return name === 'data-phx-ref-loading' && this.closing; },
    click() { this.clicks++; this.closing = true; }
  });
  const shop = closeButton();
  const battleLog = closeButton();
  env.modals.push(shop, battleLog);

  for (const modal of [shop, battleLog]) {
    modal.visible = true;
    env.listeners['phx:update']();
    await Promise.resolve();
    assert.equal(env.escape(true).defaultPrevented, true);
    assert.equal(modal.clicks, 0);
    assert.equal(env.escape().stopped, true);
    env.escape();
    assert.equal(modal.clicks, 1);
    modal.visible = false;
    env.listeners['phx:update']();
    assert.equal(env.escape().defaultPrevented, undefined);
  }
  assert.deepEqual(locks, [['Escape'], ['Escape']]);
  assert.equal(unlocks, 2);
});

test('Escape closes a modal in windowed mode or when keyboard lock is denied', async () => {
  for (const fullscreen of [false, true]) {
    let requests = 0;
    let clicks = 0;
    const keyboard = {lock() { requests++; return Promise.reject(new Error('Denied')); }, unlock() {}};
    const env = environment('/training', {fullscreen, keyboard});
    env.modals.push({getClientRects: () => [{}], hasAttribute: () => false, click: () => { clicks++; }});
    env.listeners['phx:update']();
    await Promise.resolve();
    env.listeners['phx:update']();
    assert.equal(requests, fullscreen ? 1 : 0);
    assert.equal(env.escape().defaultPrevented, true);
    assert.equal(clicks, 1);
  }
});

test('direct visits wait for an interaction and Esc is respected afterwards', async () => {
  const env = environment('/battles/12');
  assert.equal(env.requests(), 0);
  env.click(null, {inBattle: true, editable: true});
  assert.equal(env.requests(), 0);
  env.listeners.keydown({code: 'Space', key: ' ', isTrusted: true, target: {closest: () => null}});
  assert.equal(env.requests(), 1);
  await Promise.resolve();
  env.document.fullscreenElement = null;
  env.listeners.fullscreenchange();
  env.click(null, {inBattle: true});
  assert.equal(env.requests(), 1);
});

test('server navigation to a battle can use an active gesture or wait for one', () => {
  const env = environment();
  env.navigate('/matches/34');
  assert.equal(env.requests(), 0);
  env.click(null, {inBattle: true});
  assert.equal(env.requests(), 1);

  const active = environment();
  active.activation.isActive = true;
  active.navigate('/arena/56');
  assert.equal(active.requests(), 1);
});

test('normal navigation, external links, modified clicks and disabled controls do not enter', () => {
  const env = environment();
  for (const href of ['https://browsermoba.com/arena', 'https://browsermoba.com/player/1', 'https://example.com/battles/1']) {
    env.click(env.control({href}));
  }
  const battle = env.control({href: 'https://browsermoba.com/battles/12'});
  for (const options of [{ctrlKey: true}, {metaKey: true}, {shiftKey: true}, {altKey: true}, {button: 1}, {defaultPrevented: true}, {isTrusted: false}]) {
    env.click(battle, options);
  }
  env.click(env.control({launch: true, disabled: true}));
  env.click(env.control({launch: true, getAttribute: () => 'true'}));
  env.click(env.control({href: battle.href, target: '_blank'}));
  env.click(env.control({href: battle.href, hasAttribute: name => name === 'download'}));
  assert.equal(env.requests(), 0);
});

test('unsupported, denied and throwing fullscreen never interrupt battle launch', async () => {
  for (const options of [{deny: true}, {throw: true}, {}]) {
    const env = environment('/training', options);
    if (!options.deny && !options.throw) env.document.fullscreenEnabled = false;
    const event = env.click(env.control({launch: true}));
    assert.equal(event.defaultPrevented, false);
    await new Promise(resolve => setImmediate(resolve));
  }
});
