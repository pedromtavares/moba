const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^Hooks\.(InvokeStage|CombatStage|InventoryOrder|ManualCodex) = .*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.ShopViewport;');

function environment({roster = true, desktop = true} = {}) {
  let observer;
  const properties = new Map();
  const spacing = new Map();
  const tabs = {id: 'hero-team-tabs', style: {}, getBoundingClientRect: () => ({height: 65})};
  const content = {getBoundingClientRect: () => ({left: 70, right: 1188})};
  const training = {querySelector: () => content, getBoundingClientRect: () => ({top: 0}), style: {setProperty: (key, value) => spacing.set(key, value)}};
  const progress = {getClientRects: () => desktop ? [{}] : [], getBoundingClientRect: () => ({right: 620})};
  const el = {
    previousElementSibling: roster ? tabs : null,
    style: {setProperty: (key, value) => properties.set(key, value)},
    getBoundingClientRect: () => ({top: 729, left: 0, right: 1200, height: 171}),
    closest: selector => selector === '.game-page' ? {} : selector === '.team-hero-panel' ? null : training,
    querySelector: () => progress
  };
  const context = {
    document: {addEventListener() {}, removeEventListener() {}},
    module: {exports: {}}, window: {innerHeight: 900, addEventListener() {}, removeEventListener() {}},
    ResizeObserver: class {
      constructor(callback) { observer = this; this.callback = callback; }
      observe(element) { this.observed = element; }
      disconnect() { this.disconnected = true; }
    }
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  const hook = {...context.module.exports, el};
  hook.mounted();
  return {hook, tabs, el, content, properties, spacing, observer};
}

test('external roster aligns with page content and ends at the XP bar without enlarging the HUD', () => {
  const page = environment();
  assert.equal(page.properties.get('--shop-hud-height'), '171px');
  assert.equal(page.tabs.style.left, '70px');
  assert.equal(page.tabs.style.width, '550px');
  assert.equal(page.tabs.style.bottom, '170px');
  assert.equal(page.tabs.style.visibility, 'visible');
  assert.equal(page.spacing.get('--team-hud-space'), '242px');
  assert.equal(page.spacing.get('--team-page-height'), '900px');
  page.content.getBoundingClientRect = () => ({left: 90, right: 1188});
  page.el.querySelector = () => ({getClientRects: () => [{}], getBoundingClientRect: () => ({right: 700})});
  page.observer.callback();
  assert.equal(page.tabs.style.left, '90px');
  assert.equal(page.tabs.style.width, '610px');
  page.hook.destroyed();
  assert.equal(page.observer.disconnected, true);
});

test('mobile roster follows the full page content width when desktop hero stats are hidden', () => {
  const page = environment({desktop: false});
  assert.equal(page.tabs.style.left, '70px');
  assert.equal(page.tabs.style.width, '1118px');
});

test('solo HUD retains its original shop height without adding roster space', () => {
  const page = environment({roster: false});
  assert.equal(page.properties.get('--shop-hud-height'), '171px');
  assert.equal(page.spacing.size, 0);
});
