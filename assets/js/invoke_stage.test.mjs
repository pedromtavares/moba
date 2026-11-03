import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = (await readFile(new URL('./invoke_stage.js', import.meta.url), 'utf8')).replace("import InvokeCreation from './invoke_creation';", 'class InvokeCreation { destroyed() {} }');
const {InvokeArt, InvokeStage} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function artwork(t) {
  const original = globalThis.Image;
  const requests = [];
  globalThis.Image = class { constructor() { requests.push(this); } };
  t.after(() => { globalThis.Image = original; });
  const layers = [true, false].map(active => ({
    src: active ? 'juggernaut.jpg' : '',
    active,
    classList: {add() { layers.find(l => l.classList === this).active = true; }, remove() { layers.find(l => l.classList === this).active = false; }}
  }));
  const hook = {...InvokeArt, el: {dataset: {artUrl: 'juggernaut.jpg'}, querySelectorAll: () => layers}};
  hook.mounted();
  return {hook, layers, requests, select(url) { hook.el.dataset.artUrl = url; hook.updated(); }};
}

test('artwork stays visible while loading and ignores a stale hero image', t => {
  const page = artwork(t);
  page.select('axe.jpg');
  const stale = page.requests[0].onload;
  assert.equal(page.layers[0].active, true);
  page.select('lina.jpg');
  page.requests[1].onload();
  stale();
  assert.equal(page.layers[1].src, 'lina.jpg');
  assert.equal(page.layers[1].active, true);
  assert.equal(page.layers[0].active, false);
  page.hook.updated();
  assert.equal(page.requests.length, 2);
});

test('failed loads keep the previous artwork and leaving the page cancels pending changes', t => {
  const page = artwork(t);
  page.select('missing.jpg');
  page.requests[0].onerror();
  assert.equal(page.layers[0].active, true);
  page.select('axe.jpg');
  const late = page.requests[1].onload;
  page.hook.destroyed();
  assert.equal(page.requests[1].onload, null);
  late();
  assert.equal(page.layers[0].active, true);
});


test('planning mode opens at the stage top and measures viewport height independently of page scrolling', t => {
  const original = globalThis.window;
  globalThis.window = {
    innerHeight: 720, scrollY: 400,
    matchMedia: () => ({matches: true}), addEventListener() {}, removeEventListener() {}
  };
  t.after(() => { globalThis.window = original; });
  const properties = new Map();
  let scrolls = 0;
  const hook = {...InvokeStage, el: {
    dataset: {mode: 'presets'},
    querySelector: () => ({dataset: {}, querySelectorAll: () => []}),
    style: {setProperty: (key, value) => properties.set(key, value)},
    classList: {remove() {}}, addEventListener() {}, removeEventListener() {},
    getBoundingClientRect: () => ({top: 48 - window.scrollY}),
    scrollIntoView() { scrolls++; window.scrollY = 48; }
  }};
  hook.mounted();
  assert.equal(properties.get('--invoke-height'), '672px');
  hook.el.dataset.mode = 'custom';
  hook.updated();
  assert.equal(scrolls, 1);
  assert.equal(properties.get('--invoke-height'), '672px');
  hook.updated();
  assert.equal(scrolls, 1);
  hook.el.dataset.mode = 'presets';
  hook.updated();
  assert.equal(scrolls, 2);
  hook.destroyed();
});
