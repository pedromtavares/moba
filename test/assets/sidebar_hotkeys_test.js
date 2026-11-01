const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/sidebar_hotkeys.js', 'utf8')
  .replace('export function initSidebarHotkeys()', 'function initSidebarHotkeys()') + '\ninitSidebarHotkeys();';

function environment() {
  let handler;
  const state = {battle: false, dialogs: [], links: {}};
  for (const key of ['1', '2', '3', '4', '5', '6']) {
    state.links[key] = {
      clicks: 0, visible: true, disabled: false,
      getClientRects() { return this.visible ? [{}] : []; },
      getAttribute() { return this.disabled ? 'true' : null; },
      click() { this.clicks++; }
    };
  }
  vm.runInNewContext(source, {document: {
    addEventListener: (_event, listener) => { handler = listener; },
    querySelector: selector => selector === '#battle-page'
      ? state.battle : state.links[selector.match(/hotkey="([1-6])"/)?.[1]],
    querySelectorAll: () => state.dialogs
  }});
  state.press = (key, options = {}) => {
    const event = {
      key, defaultPrevented: false, target: {closest: () => null},
      preventDefault() { this.defaultPrevented = true; }, ...options
    };
    handler(event);
    return event;
  };
  return state;
}

test('1–6 activate the existing sidebar links, retaining LiveView navigation', () => {
  const env = environment();
  for (const key of Object.keys(env.links)) {
    assert.equal(env.press(key).defaultPrevented, true);
    assert.equal(env.links[key].clicks, 1);
  }
});

test('battle item keys, typing, held keys and browser shortcuts never navigate', () => {
  const env = environment();
  env.battle = true;
  assert.equal(env.press('1').defaultPrevented, false);
  env.battle = false;
  for (const options of [
    {target: {closest: () => ({})}}, {repeat: true}, {isComposing: true},
    {ctrlKey: true}, {metaKey: true}, {altKey: true}, {shiftKey: true}, {defaultPrevented: true}
  ]) env.press('1', options);
  env.press('7');
  assert.equal(env.links['1'].clicks, 0);
});

test('missing, hidden and disabled destinations and open dialogs are ignored', () => {
  const env = environment();
  delete env.links['2']; // Locked guest Arena has no shortcut.
  env.links['3'].visible = false;
  env.links['4'].disabled = true;
  for (const key of ['2', '3', '4']) assert.equal(env.press(key).defaultPrevented, false);
  env.dialogs.push({getClientRects: () => [{}]});
  assert.equal(env.press('1').defaultPrevented, false);
  assert.equal(env.links['1'].clicks, 0);
});
