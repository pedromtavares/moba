const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^Hooks\.\w+ = \{\.\.\..*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.BattleContinueHotkey;');

function environment() {
  const listeners = {};
  const controls = {};
  const dialogs = [];
  const root = {
    dataset: {finished: 'true'},
    querySelector: selector => controls[selector],
    addEventListener: (event, handler) => { listeners[event] = handler; },
    removeEventListener: (event, handler) => { if (listeners[event] === handler) delete listeners[event]; }
  };
  const bar = {querySelector: root.querySelector};
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
  function click({inside = true, interactive = null, ...options} = {}) {
    listeners.click?.({
      button: 0,
      target: {closest: selector => selector === '#battle-bar' ? (inside ? bar : null) : interactive},
      ...options
    });
  }
  return {root, controls, dialogs, listeners, control, press, click, destroy: () => continuation.destroyed.call(hook)};
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

test('clicking result content forwards to the existing primary action', () => {
  const env = environment();
  const action = env.control('[data-battle-continue=true]', {tagName: 'BUTTON'});
  env.click();
  assert.equal(action.clicks, 1);
  env.click({interactive: action});
  assert.equal(action.clicks, 1);
});

test('only a plain click in a finished result bar can forward', () => {
  const env = environment();
  const action = env.control('#load-training');
  env.root.dataset.finished = 'false';
  env.click();
  env.root.dataset.finished = 'true';
  for (const options of [
    {inside: false}, {interactive: {}}, {button: 1}, {defaultPrevented: true},
    {altKey: true}, {ctrlKey: true}, {metaKey: true}, {shiftKey: true}
  ]) env.click(options);
  action.disabled = true;
  env.click();
  action.disabled = false;
  env.dialogs.push({getClientRects: () => [{}]});
  env.click();
  assert.equal(action.clicks, 0);
});

test('leaving the battle removes the continuation listener', () => {
  const env = environment();
  const action = env.control('[data-battle-continue=true]');
  env.destroy();
  assert.equal(env.listeners.keydown, undefined);
  assert.equal(env.listeners.click, undefined);
  env.press();
  assert.equal(action.clicks, 0);
});
