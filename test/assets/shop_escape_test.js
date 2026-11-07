const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^Hooks\.(InvokeStage|CombatStage|InventoryOrder|ManualCodex) = .*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.ShopEscape;');

function environment(options = {}) {
  const listeners = new Map();
  const state = {visible: false, closed: 0, locks: [], unlocks: 0, inspected: []};
  const document = {
    fullscreenElement: options.fullscreen ? {} : null,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name)
  };
  const keyboard = options.unsupported ? undefined : {
    lock(keys) { state.locks.push(Array.from(keys)); return options.denied ? Promise.reject(new Error('Denied')) : Promise.resolve(); },
    unlock() { state.unlocks++; }
  };
  const context = {module: {exports: {}}, document, navigator: {keyboard}, Promise};
  vm.createContext(context); vm.runInContext(source, context);
  const hook = {...context.module.exports,
    el: {getClientRects: () => state.visible ? [{}] : [], getAttribute: () => options.component ? '7' : null,
      querySelector: () => ({dataset: {recipeRarity: state.recipe}}),
      querySelectorAll: selector => (selector === '.shop-shelf' ? state.rows : state.actions) || []},
    pushEvent: () => { state.closed++; }, pushEventTo: (target, event, params, reply) => {
      if (event === 'close-shop') { state.closed++; state.component = true; }
      else { state.inspected.push({target, event, params, reply}); if (!state.defer) reply(); }
    }
  };
  hook.mounted();
  state.show = visible => { state.visible = visible; hook.updated(); };
  state.press = (key, extra = {}) => {
    const event = {key, code: key === ' ' ? 'Space' : key, preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; }, ...extra};
    listeners.get('keydown')(event); return event;
  };
  state.escape = repeat => state.press('Escape', {repeat});
  return {state, hook, document, listeners};
}

test('Escape closes the visible shop and releases its Escape lock when it hides', async () => {
  const {state} = environment({fullscreen: true});
  state.show(true); await Promise.resolve();
  assert.deepEqual(state.locks, [['Escape']]);
  const event = state.escape();
  assert.equal(state.closed, 1); assert.equal(event.prevented, true); assert.equal(event.stopped, true);
  state.show(false); assert.equal(state.unlocks, 1);
  assert.equal(state.escape().prevented, undefined);
});

test('the shop locks only in fullscreen, closes via its component, and cleans up on navigation', async () => {
  const {state, document, listeners, hook} = environment({component: true});
  state.show(true); assert.equal(state.locks.length, 0);
  document.fullscreenElement = {}; listeners.get('fullscreenchange')(); await Promise.resolve();
  assert.equal(state.locks.length, 1);
  state.escape(true); assert.equal(state.closed, 0);
  state.escape(); assert.equal(state.component, true);
  hook.destroyed(); assert.equal(state.unlocks, 1); assert.equal(listeners.size, 0);
});

test('unsupported or denied keyboard locking still lets Escape close the shop', async () => {
  for (const options of [{unsupported: true}, {denied: true}]) {
    const {state} = environment({...options, fullscreen: true});
    state.show(true); await new Promise(resolve => setImmediate(resolve));
    state.escape(); assert.equal(state.closed, 1);
  }
});

test('F closes only the visible shop, without capturing typing, modifiers or held keys', () => {
  const {state} = environment({component: true});
  assert.equal(state.press('f').prevented, undefined);
  state.show(true);
  state.press('F');
  assert.equal(state.closed, 1);
  assert.equal(state.component, true);
  for (const extra of [{repeat: true}, {ctrlKey: true}, {altKey: true}, {target: {closest: () => ({})}}]) state.press('f', extra);
  assert.equal(state.closed, 1);
});

test('arrows inspect items immediately; Space activates actions and skips unavailable ingredients', () => {
  const {state} = environment();
  const button = (id, selected = false, unavailable = false) => ({
    id, clicks: 0, classList: {contains: () => id.includes('item')},
    getClientRects: () => [{}], getAttribute: name => ({'aria-pressed': String(selected), 'aria-disabled': String(unavailable),
      'phx-click': id.includes('item') ? 'select-inventory' : 'select-category', 'phx-value-code': id,
      'phx-value-rarity': id, 'phx-target': '7'})[name],
    focus() { state.focused = this; }, click() { this.clicks++; }
  });
  const inventory = button('inventory', true), item = button('inventory-item');
  const normal = button('normal'), boots = button('boots-item'), disabled = button('disabled-item', false, true);
  const rare = button('rare'), rareItem = button('rare-item');
  state.rows = [[inventory, item], [normal, disabled, boots], [rare, rareItem]].map(row => ({querySelectorAll: () => row}));
  state.show(true);
  state.press('ArrowRight'); assert.equal(state.focused, item); assert.equal(item.clicks, 0);
  assert.equal(state.inspected.at(-1).params.code, item.id);
  state.press(' '); assert.equal(item.clicks, 0);
  state.press(' ', {repeat: true}); assert.equal(item.clicks, 0);
  state.press('ArrowDown'); assert.equal(state.focused, boots);
  assert.equal(state.inspected.at(-1).params.code, boots.id);
  state.press('ArrowDown'); assert.equal(state.focused, rareItem);
  state.press('ArrowDown'); assert.equal(state.focused, item);
  const buy = button('buy');
  state.actions = [buy];
  state.press(' '); assert.equal(buy.clicks, 1);
  state.press(' ', {repeat: true}); assert.equal(buy.clicks, 1);
  state.press('ArrowRight'); assert.equal(state.focused, buy);
  const buyFocus = {closest: selector => selector.startsWith('input') ? null : buy};
  assert.equal(state.press(' ', {target: buyFocus}).prevented, true);
  assert.equal(buy.clicks, 2);
  state.press('ArrowLeft', {target: buyFocus}); assert.equal(state.focused, item);
  state.press('ArrowLeft'); assert.equal(state.focused, inventory);
  const focused = {closest: selector => selector.startsWith('input') ? null : boots};
  state.press(' ', {target: focused}); assert.equal(boots.clicks, 0); assert.equal(buy.clicks, 3);
  state.defer = true;
  state.press('ArrowRight');
  state.press(' '); assert.equal(buy.clicks, 3, 'do not activate an action for stale details');
  state.inspected.at(-1).reply();
  state.press(' '); assert.equal(buy.clicks, 4);
  state.recipe = 'normal';
  const inspections = state.inspected.length;
  state.press('ArrowDown');
  assert.equal(state.inspected.length, inspections, 'browsing never adds recipe ingredients');
  state.press(' '); assert.equal(boots.clicks, 1, 'Space explicitly adds a recipe ingredient');
  for (const extra of [{altKey: true}, {isComposing: true}, {defaultPrevented: true}, {target: {closest: () => ({})}}]) {
    assert.equal(state.press('ArrowRight', extra).prevented, undefined);
  }
  const action = {closest: selector => selector.startsWith('input') ? null : {}};
  assert.equal(state.press(' ', {target: action}).prevented, undefined);
  state.show(false); assert.equal(state.press(' ').prevented, undefined);
});
