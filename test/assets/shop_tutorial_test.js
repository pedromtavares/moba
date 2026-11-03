const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/shop_tutorial.js', 'utf8')
  .replace(/^import .*;$/gm, '').replace(/export function /g, 'function ');
const context = {};
vm.runInNewContext(source, context);
const action = context.shopTutorialAction;
const normals = [
  {code: 'boots_of_speed', name: 'Boots of Speed'},
  {code: 'sages_mask', name: "Sage's Mask"},
  {code: 'chainmail', name: 'Chainmail'}
];
const state = overrides => ({owned: [], selected: '', normalItems: normals, inventory: [], recipe: [], ...overrides});

test('first upgrades point at Boots, Buy, Mask, Buy and wait for actual ownership', () => {
  let current = state({selected: 'boots_of_speed', inspected: false});
  assert.equal(action(3, current).title, 'Choose Boots of Speed');
  current.inspected = true;
  assert.equal(action(3, current).selector, '#buy-button');
  assert.equal(action(3, current).title, 'Buy Boots of Speed');
  assert.equal(action(3, current).selector, '#buy-button', 'no ownership change means no advancement');
  current.owned = ['boots_of_speed'];
  assert.equal(action(3, current).title, "Choose Sage's Mask");
  current.selected = 'sages_mask';
  assert.equal(action(3, current).selector, '#buy-button');
  assert.equal(action(3, current).title, "Buy Sage's Mask");
  current.owned.push('sages_mask');
  assert.equal(action(3, current), null);
});

test('existing purchases and a different first item do not trap the upgrade guide', () => {
  assert.equal(action(3, state({owned: ['sages_mask']})).title, 'Choose Boots of Speed');
  assert.equal(action(3, state({owned: ['chainmail']})).title, 'Choose Boots of Speed');
  assert.equal(action(6, state({owned: ['boots_of_speed', 'sages_mask']})).title, 'Choose Chainmail');
  assert.equal(action(6, state({owned: ['boots_of_speed', 'sages_mask'], selected: 'chainmail'})).selector, '#buy-button');
});

test('transmutation points at the rare item, its action, each ingredient and the final action', () => {
  assert.equal(action(7, state({selectedRarity: 'normal'})).title, 'Choose Tranquil Boots');
  assert.equal(action(7, state({selectedRarity: 'rare'})).selector, '#start-transmute');
  const inventory = [...normals.map(item => ({...item, rarity: 'normal'})), {code: 'dagon', name: 'Dagon', rarity: 'epic'}];
  const current = state({inventory, recipeRarity: 'normal', recipeCount: 3});
  for (const item of normals) {
    assert.equal(action(8, current).selector, `#inventory button[phx-value-code="${item.code}"]`);
    current.recipe.push(item.code);
  }
  assert.equal(action(8, current).selector, '#finish-transmute');
});

test('the pointer follows server patches and disconnects when the tutorial stops', () => {
  let pending, changed, disconnected = false, visible = true;
  const pointers = [];
  const owned = [];
  const shop = {
    dataset: {selectedCode: 'boots_of_speed', selectedRarity: 'normal', itemInspected: 'false'},
    querySelectorAll(selector) {
      return selector.includes('inventory')
        ? owned.map(code => ({dataset: {rarity: 'normal'}, getAttribute: name => ({'phx-value-code': code, 'aria-label': normals.find(item => item.code === code).name, 'aria-pressed': 'false'}[name])}))
        : normals.map(item => ({getAttribute: name => name === 'phx-value-code' ? item.code : item.name}));
    },
    querySelector(selector) { return targets[selector] ||= {getClientRects: () => [{}]}; }
  };
  const targets = {};
  const modal = {querySelector: () => shop, classList: {contains: () => visible}};
  let tour;
  class Tour {
    constructor() { tour = this; this.events = {}; }
    on(name, fn) { this.events[name] = fn; }
    addStep(options) {
      pointers.push(options);
      this.step = {updateStepOptions: options => pointers.push(options), show() {}};
      return this.step;
    }
    start() { this.started = true; }
    hide() { this.hidden = true; }
    complete() { this.events.complete(); }
  }
  const env = {Shepherd: {Tour}, offset() {}, shift() {},
    document: {getElementById: () => modal, body: {classList: {add() {}, remove() {}}}},
    requestAnimationFrame(fn) { pending = fn; return 1; }, cancelAnimationFrame() { pending = null; },
    MutationObserver: class {constructor(fn) { changed = fn; } observe() {} disconnect() { disconnected = true; }}
  };
  vm.runInNewContext(source, env);
  const hook = {};
  env.startShopTutorial(hook, 3);
  const flush = () => { const fn = pending; pending = null; fn?.(); };
  flush();
  assert.equal(pointers.at(-1).label, 'Choose Boots of Speed');
  shop.dataset.itemInspected = 'true'; changed(); flush();
  assert.equal(pointers.at(-1).attachTo.element, '#buy-button');
  owned.push('boots_of_speed'); changed(); flush();
  assert.equal(pointers.at(-1).label, "Choose Sage's Mask");
  visible = false; changed(); flush(); assert.equal(tour.hidden, true);
  hook.gameShopTutorial.stop();
  assert.equal(disconnected, true);
  assert.equal(pending, null);
});
