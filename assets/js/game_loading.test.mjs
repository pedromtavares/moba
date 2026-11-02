import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const source = await readFile(new URL('./game_loading.js', import.meta.url), 'utf8');
const {initGameLoading} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function setup(t) {
  const originals = Object.fromEntries(['window', 'document', 'setInterval', 'clearInterval', 'setTimeout', 'clearTimeout'].map(key => [key, globalThis[key]]));
  t.after(() => Object.assign(globalThis, originals));
  const element = () => ({
    inert: false, hidden: true, dataset: {}, style: {setProperty() {}}, attributes: new Map(),
    getAttribute(name) { return this.attributes.get(name) ?? null; },
    setAttribute(name, value) { this.attributes.set(name, value); },
    removeAttribute(name) { this.attributes.delete(name); }
  });
  const main = element();
  const nodes = Object.fromEntries(['game-loading-screen', 'game-loading-fill', 'game-loading-progress', 'game-loading-icon'].map(id => [id, element()]));
  nodes['main-wrapper'] = main;
  const listeners = {};
  const timers = new Map();
  let nextTimer = 0;
  globalThis.window = {location: {href: 'http://localhost/battles/1'}, addEventListener(name, callback) { listeners[name] = callback; }};
  globalThis.document = {getElementById: id => nodes[id], addEventListener() {}};
  globalThis.setInterval = () => ++nextTimer;
  globalThis.clearInterval = () => {};
  globalThis.setTimeout = callback => { const id = ++nextTimer; timers.set(id, callback); return id; };
  globalThis.clearTimeout = id => timers.delete(id);
  initGameLoading();
  return {
    main, nodes, element,
    emit(name, detail) { listeners[name]({detail}); },
    complete() { [...timers.values()].forEach(callback => callback()); timers.clear(); }
  };
}

test('returning from battle releases the outer wrapper when training restores the sidebar', t => {
  const page = setup(t);
  const transition = {kind: 'redirect', to: '/training'};
  page.emit('phx:page-loading-start', transition);
  assert.equal(page.main.inert, true);
  page.nodes['game-content'] = page.element();
  page.emit('phx:page-loading-stop', transition);
  page.complete();
  assert.equal(page.main.inert, false);
  assert.equal(page.main.getAttribute('aria-busy'), null);
  assert.equal(page.nodes['game-content'].inert, false);
  assert.equal(page.nodes['game-loading-screen'].hidden, true);
});

test('overlapping loads release every original container and preserve its prior accessibility state', t => {
  const page = setup(t);
  const initial = {kind: 'initial'};
  const redirect = {kind: 'redirect', to: '/training'};
  page.main.setAttribute('aria-busy', 'false');
  page.emit('phx:page-loading-start', initial);
  const content = page.element();
  content.inert = true;
  content.setAttribute('aria-busy', 'true');
  page.nodes['game-content'] = content;
  page.emit('phx:page-loading-start', redirect);
  page.emit('phx:page-loading-stop', initial);
  assert.equal(page.main.inert, true);
  page.emit('phx:page-loading-stop', redirect);
  page.complete();
  assert.equal(page.main.inert, false);
  assert.equal(page.main.getAttribute('aria-busy'), 'false');
  assert.equal(content.inert, true);
  assert.equal(content.getAttribute('aria-busy'), 'true');
});

test('a failed navigation also releases the original container after a layout change', t => {
  const page = setup(t);
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/training'});
  page.nodes['game-content'] = page.element();
  page.emit('phx:page-loading-start', {kind: 'error'});
  assert.equal(page.main.inert, false);
  assert.equal(page.nodes['game-loading-screen'].hidden, true);
});
