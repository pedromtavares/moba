const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/game_fullscreen.js', 'utf8')
  .replace('export function initGameFullscreen()', 'function initGameFullscreen()') + '\ninitGameFullscreen();';

function environment(path = '/training', options = {}) {
  const listeners = {};
  const document = {
    fullscreenElement: options.fullscreen ? {tagName: 'HTML'} : null,
    fullscreenEnabled: true,
    addEventListener: (event, listener) => { listeners[event] = listener; }
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
    URL, Promise, document, navigator: {userActivation: activation},
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
  return {document, listeners, activation, click, control, navigate, requests: () => requests, fullscreenOptions: () => fullscreenOptions};
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
