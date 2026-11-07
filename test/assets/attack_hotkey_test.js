const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^Hooks\.(InvokeStage|CombatStage|InventoryOrder|ManualCodex) = .*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.AttackButton;');

function environment() {
  const listeners = {};
  const clicks = {};
  const sent = [];
  const dialogs = [];
  const button = {
    closest: () => null, disabled: false, visible: true, dataset: {hero: '42'},
    attributes: {'data-skill': '7', 'data-item': '8'},
    addEventListener: (event, handler) => { clicks[event] = handler; },
    getClientRects: () => button.visible ? [{}] : [],
    click() { if (!this.disabled) clicks.click({stopPropagation() {}}); }
  };
  const context = {
    module: {exports: {}},
    window: {
      addEventListener: (event, handler) => { listeners[event] = handler; },
      removeEventListener: (event, handler) => { if (listeners[event] === handler) delete listeners[event]; }
    },
    document: {querySelectorAll: () => dialogs},
    $: element => ({
      attr: name => element.attributes[name],
      find: () => ({html() {}}),
      prop: (name, value) => { element[name] = value; }
    })
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  const hook = {el: button, pushEvent: (event, payload) => sent.push({event, payload})};
  const attack = context.module.exports;
  attack.mounted.call(hook);

  function press(options = {}) {
    const event = {
      code: 'Space', target: {closest: () => false}, defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; }, ...options
    };
    listeners.keydown?.(event);
    return event;
  }
  return {button, sent, dialogs, press, listeners, destroy: () => attack.destroyed.call(hook)};
}

test('Space attacks with the selected skill and item and prevents page scrolling', () => {
  const env = environment();
  assert.equal(env.press().defaultPrevented, true);
  assert.equal(env.sent.length, 1);
  assert.equal(env.sent[0].event, 'next-turn');
  assert.equal(env.sent[0].payload.skill_id, '7');
  assert.equal(env.sent[0].payload.item_id, '8');
  assert.equal(env.sent[0].payload.hero_id, '42');
  assert.equal(env.button.disabled, true);
  env.press();
  assert.equal(env.sent.length, 1);
});

test('typing, interactive controls, held keys and modified shortcuts do not attack', () => {
  const env = environment();
  for (const options of [
    {target: {closest: () => true}}, {repeat: true}, {isComposing: true},
    {altKey: true}, {ctrlKey: true}, {metaKey: true}, {shiftKey: true},
    {code: 'Enter'}, {defaultPrevented: true}
  ]) env.press(options);
  assert.equal(env.sent.length, 0);
});

test('hidden buttons and modal dialogs prevent Space attacks', () => {
  const env = environment();
  env.button.visible = false;
  assert.equal(env.press().defaultPrevented, false);
  env.button.visible = true;
  env.dialogs.push({getClientRects: () => [{}]});
  assert.equal(env.press().defaultPrevented, false);
  assert.equal(env.sent.length, 0);
});

test('leaving the battle removes the Space listener', () => {
  const env = environment();
  env.destroy();
  assert.equal(env.listeners.keydown, undefined);
  env.press();
  assert.equal(env.sent.length, 0);
});
