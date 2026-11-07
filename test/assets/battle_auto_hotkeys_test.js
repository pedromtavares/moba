const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^Hooks\.(InvokeStage|CombatStage|InventoryOrder|ManualCodex) = .*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.BattleAutoHotkeys;');

function page() {
  const listeners = {};
  const controls = {};
  const dialogs = [];
  const context = {module: {exports: {}}, document: {querySelectorAll: () => dialogs}, window: {
    addEventListener: (name, listener) => { listeners[name] = listener; },
    removeEventListener: name => { delete listeners[name]; }
  }};
  vm.runInNewContext(source, context);
  const hook = {...context.module.exports, el: {querySelector: selector => controls[selector]}};
  hook.mounted();
  const control = selector => controls[selector] = {clicks: 0, disabled: false, visible: true,
    getAttribute() { return null; }, getClientRects() { return this.visible ? [{}] : []; }, click() { this.clicks++; }};
  const press = (key, options = {}) => {
    const event = {key, target: {closest: () => null}, preventDefault() { this.defaultPrevented = true; }, ...options};
    listeners.keydown?.(event); return event;
  };
  return {control, press, dialogs, hook, listeners};
}

test('T starts the displayed auto battle, and G starts all battles', () => {
  const p = page(), battle = p.control('#training-auto-battle'), all = p.control('#training-auto-match');
  assert.equal(p.press('t').defaultPrevented, true);
  assert.equal(battle.clicks, 1); assert.equal(all.clicks, 0);
  assert.equal(p.press('g').defaultPrevented, true);
  assert.equal(all.clicks, 1);
  p.press('x'); assert.equal(battle.clicks, 1);
});

test('auto hotkeys protect typing, dialogs, modifiers, held keys and disabled or hidden controls', () => {
  const p = page(), battle = p.control('#training-auto-battle');
  for (const options of [{repeat: true}, {isComposing: true}, {defaultPrevented: true}, {altKey: true}, {ctrlKey: true}, {metaKey: true}, {shiftKey: true}, {target: {closest: () => ({})}}]) p.press('t', options);
  p.dialogs.push({getClientRects: () => [{}], contains: () => false}); p.press('t');
  p.dialogs.length = 0;
  battle.disabled = true; p.press('t');
  battle.disabled = false; battle.visible = false; p.press('t');
  assert.equal(battle.clicks, 0);
  assert.equal(p.press('g').defaultPrevented, undefined);
});

test('auto hotkeys are removed when leaving the battle', () => {
  const p = page(), battle = p.control('#training-auto-battle');
  p.hook.destroyed(); p.press('t');
  assert.equal(battle.clicks, 0); assert.equal(p.listeners.keydown, undefined);
});
