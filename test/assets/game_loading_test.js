const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/game_loading.js', 'utf8')
  .replace('export function initGameLoading()', 'function initGameLoading()') + '\ninitGameLoading();';

function environment(authenticated = true) {
  const listeners = {};
  const timers = new Map();
  const intervals = new Map();
  let nextId = 0;
  const node = () => ({
    hidden: true, dataset: {}, attributes: {},
    style: {setProperty(name, value) { this[name] = value; }},
    setAttribute(name, value) { this.attributes[name] = value; },
    removeAttribute(name) { delete this.attributes[name]; }
  });
  const screen = node(), progress = node(), fill = node(), content = node(), icon = node();
  const sidebar = {visible: true, right: 124,
    getClientRects() { return this.visible ? [{}] : []; },
    getBoundingClientRect() { return {right: this.right}; }};
  const topnav = {visible: false,
    getClientRects() { return this.visible ? [{}] : []; },
    getBoundingClientRect() { return {bottom: 64}; }};
  const elements = {'game-loading-screen': authenticated && screen,
    'game-loading-progress': progress, 'game-loading-fill': fill, 'game-loading-icon': icon,
    'game-content': content, 'game-sidebar': sidebar, topnav};
  const addEventListener = (name, handler) => { listeners[name] = handler; };
  vm.runInNewContext(source, {
    document: {getElementById: id => elements[id], addEventListener},
    window: {location: new URL('http://localhost/base'), addEventListener}, URL,
    setInterval: fn => { intervals.set(++nextId, fn); return nextId; },
    clearInterval: id => intervals.delete(id),
    setTimeout: fn => { timers.set(++nextId, fn); return nextId; },
    clearTimeout: id => timers.delete(id)
  });
  return {
    screen, progress, fill, content, icon, sidebar, topnav, listeners,
    start(detail) { listeners['phx:page-loading-start']({detail}); },
    stop(detail) { listeners['phx:page-loading-stop']({detail}); },
    tick() { for (const fn of intervals.values()) fn(); },
    finish() { for (const [id, fn] of timers) { timers.delete(id); fn(); } },
    click(href, attributes = [], overrides = {}) {
      const link = {href, hasAttribute: name => attributes.includes(name)};
      listeners.click({button: 0, target: {closest: () => link}, ...overrides});
    }
  };
}

test('navigation keeps the sidebar available and completes progress only when ready', () => {
  const env = environment();
  const navigation = {kind: 'redirect'};
  env.start(navigation);
  assert.equal(env.screen.hidden, false);
  assert.equal(env.screen.style['--loading-left'], '124px');
  assert.equal(env.screen.style['--loading-top'], '0px');
  assert.equal(env.content.inert, true);
  assert.equal(env.content.attributes['aria-busy'], 'true');
  env.tick();
  assert.ok(parseFloat(env.fill.style.width) > 8);
  for (let i = 0; i < 100; i++) env.tick();
  assert.ok(parseFloat(env.fill.style.width) <= 90);
  assert.equal(env.progress.attributes['aria-valuenow'], undefined);
  env.stop(navigation);
  assert.equal(env.fill.style.width, '100%');
  assert.equal(env.progress.attributes['aria-valuenow'], '100');
  assert.equal(env.screen.dataset.state, 'complete');
  assert.equal(env.content.inert, false);
  env.finish();
  assert.equal(env.screen.hidden, true);
});

test('nested joins wait for both completions and superseded navigation cannot dismiss a newer screen', () => {
  const env = environment();
  const navigation = {kind: 'redirect'}, join = {kind: 'initial'};
  env.start(navigation);
  env.start(join);
  env.stop(navigation);
  env.finish();
  assert.equal(env.screen.dataset.state, 'loading');
  env.stop(join);
  const next = {kind: 'patch'};
  env.start(next);
  env.stop(join);
  env.finish();
  assert.equal(env.screen.dataset.state, 'loading');
  env.stop(next);
  env.finish();
  assert.equal(env.screen.hidden, true);
});

test('ordinary actions stay unobstructed, errors and browser restoration clear the screen', () => {
  const env = environment();
  env.start({kind: 'element'});
  assert.equal(env.screen.hidden, true);
  env.start({kind: 'redirect'});
  env.start({kind: 'error'});
  assert.equal(env.screen.hidden, true);
  assert.equal(env.content.inert, false);
  env.start({kind: 'initial'});
  env.listeners.pageshow({persisted: true});
  assert.equal(env.screen.hidden, true);
});

test('the screen follows resized navigation and leaves mobile navigation exposed', () => {
  const env = environment();
  env.start({kind: 'initial'});
  env.sidebar.visible = false;
  env.topnav.visible = true;
  env.listeners.resize();
  assert.equal(env.screen.style['--loading-left'], '0px');
  assert.equal(env.screen.style['--loading-top'], '64px');
});

test('full page links show the loader while LiveView controls its own navigation', () => {
  for (const [href, attributes, options] of [
    ['http://localhost/base#hero'], ['https://other.example/path'], ['mailto:help@example.com'],
    ['http://localhost/library', ['download']], ['http://localhost/library', ['phx-click']],
    ['http://localhost/library', ['data-phx-link']], ['http://localhost/users/log_out', ['data-method']],
    ['http://localhost/library', [], {ctrlKey: true}],
    ['http://localhost/library', [], {defaultPrevented: true}],
    ['http://[invalid']
  ]) {
    const env = environment();
    env.click(href, attributes, options);
    assert.equal(env.screen.hidden, true, href);
  }
  const env = environment();
  env.click('http://localhost/users/settings');
  assert.equal(env.screen.hidden, false);
});

test('guests do not install the authenticated loading screen', () => {
  assert.deepEqual(Object.keys(environment(false).listeners), []);
});

test('each destination uses its navigation emblem, falling back to the sidebar helmet', () => {
  const env = environment();
  for (const [path, emblem] of [
    ['/base', 'base'], ['/training', 'training'], ['/invoke', 'training'],
    ['/battles/123', 'training'], ['/arena', 'arena'], ['/matches/123', 'arena'],
    ['/tavern?tab=skills', 'tavern'], ['/community', 'community'], ['/library', 'manual'],
    ['/admin/players', 'admin'], ['/player/2', 'profile'], ['/hero/123', 'profile'],
    ['/unknown', 'profile'], ['http://[invalid', 'profile']
  ]) {
    env.start({kind: 'redirect', to: `http://localhost${path}`});
    assert.equal(env.icon.src, `/images/navigation/${emblem}.webp`, path);
  }
  env.start({kind: 'initial'});
  assert.equal(env.icon.src, '/images/navigation/base.webp');
});
