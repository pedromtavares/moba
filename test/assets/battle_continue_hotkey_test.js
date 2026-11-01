const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.BattleContinueHotkey;');

function environment() {
  const listeners = {};
  const controls = {};
  const dialogs = [];
  const root = {dataset: {finished: 'true'}, querySelector: selector => controls[selector]};
  const context = {
    module: {exports: {}},
    window: {
      addEventListener: (event, handler) => { listeners[event] = handler; },
      removeEventListener: (event, handler) => { if (listeners[event] === handler) delete listeners[event]; }
    },
    document: {querySelectorAll: () => dialogs}
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  const hook = {el: root};
  const continuation = context.module.exports;
  continuation.mounted.call(hook);

  function control(selector, options = {}) {
    const element = {
      tagName: 'A', visible: true, disabled: false, clicks: 0,
      getAttribute() { return this.ariaDisabled || null; },
      getClientRects() { return this.visible ? [{}] : []; },
      click() { this.clicks++; }, ...options
    };
    controls[selector] = element;
    return element;
  }
  function press(options = {}) {
    const event = {
      code: 'Space', target: {closest: () => null}, defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; }, ...options
    };
    listeners.keydown?.(event);
    return event;
  }
  return {root, controls, dialogs, listeners, control, press, destroy: () => continuation.destroyed.call(hook)};
}

test('Space chooses the primary continuation instead of the battle log', () => {
  const env = environment();
  const training = env.control('[data-battle-continue=true]');
  const log = env.control('#load-battles');
  assert.equal(env.press().defaultPrevented, true);
  assert.equal(training.clicks, 1);
  assert.equal(log.clicks, 0);
});

test('Space continues league stages, training returns, duel rounds, match returns and guest results', () => {
  for (const selector of [
    '#league-next-battle', '#load-training', '#load-battles', '#league-battle-over',
    '#battle-over-duel', '#battle-over-training', '#battle-guest-create'
  ]) {
    const env = environment();
    const action = env.control(selector);
    assert.equal(env.press().defaultPrevented, true, selector);
    assert.equal(action.clicks, 1, selector);
  }
});

test('active battles, typing, other controls, repeated and modified keys do not continue', () => {
  const env = environment();
  const action = env.control('[data-battle-continue=true]');
  env.root.dataset.finished = 'false';
  assert.equal(env.press().defaultPrevented, false);
  env.root.dataset.finished = 'true';
  for (const options of [
    {target: {closest: () => ({tagName: 'INPUT'})}},
    {target: {closest: () => ({tagName: 'BUTTON'})}},
    {target: {closest: () => ({tagName: 'A'})}},
    {repeat: true}, {isComposing: true}, {altKey: true}, {ctrlKey: true},
    {metaKey: true}, {shiftKey: true}, {code: 'Enter'}, {defaultPrevented: true}
  ]) env.press(options);
  assert.equal(action.clicks, 0);
});

test('hidden, disabled or absent actions and visible dialogs do not continue', () => {
  const env = environment();
  assert.equal(env.press().defaultPrevented, false);
  const action = env.control('[data-battle-continue=true]');
  for (const options of [{visible: false}, {disabled: true}, {ariaDisabled: 'true'}]) {
    Object.assign(action, {visible: true, disabled: false, ariaDisabled: null}, options);
    assert.equal(env.press().defaultPrevented, false);
  }
  Object.assign(action, {visible: true, disabled: false, ariaDisabled: null});
  env.dialogs.push({getClientRects: () => [{}]});
  assert.equal(env.press().defaultPrevented, false);
  assert.equal(action.clicks, 0);
});

test('focused continuation links work and focused buttons retain native Space activation', () => {
  const env = environment();
  const action = env.control('[data-battle-continue=true]');
  assert.equal(env.press({target: {closest: () => action}}).defaultPrevented, true);
  assert.equal(action.clicks, 1);
  action.tagName = 'BUTTON';
  assert.equal(env.press({target: {closest: () => action}}).defaultPrevented, false);
  assert.equal(action.clicks, 1);
});

test('leaving the battle removes the continuation listener', () => {
  const env = environment();
  const action = env.control('[data-battle-continue=true]');
  env.destroy();
  assert.equal(env.listeners.keydown, undefined);
  env.press();
  assert.equal(action.clicks, 0);
});
