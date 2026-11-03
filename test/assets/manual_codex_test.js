const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/manual_codex.js', 'utf8').replace('export default ManualCodex;', 'ManualCodex;');

function fixture({reduced = false, width = 1440, kind = 'skill', levels = [5, 5, 3]} = {}) {
  function node(dataset = {}) {
    const attributes = new Map();
    return {dataset, hidden: false,
      setAttribute: (key, value) => attributes.set(key, value), getAttribute: key => attributes.get(key),
      focus() { this.focused = true; }, closest(selector) { return selector === '[data-manual-ranked]' ? this.group : this; },
      scrollIntoView() { this.scrolled = true; },
      animate() { return {cancel() { this.cancelled = true; }}; }};
  }
  const codes = kind === 'avatar' ? ['juggernaut', 'axe', 'lina'] : ['blink_strike', 'empower', 'decay'];
  const choices = codes.map(code => node({manualPick: kind, code}));
  choices.forEach((choice, index) => choice.setAttribute('aria-pressed', String(index === 0)));
  const details = codes.map((code, index) => Object.assign(node({manualDetail: kind, code}), {hidden: index !== 0}));
  const groups = details.map((detail, index) => {
    const buttons = Array.from({length: levels[index]}, (_, i) => node({manualRank: String(i + 1)}));
    const panels = Array.from({length: levels[index]}, (_, i) => Object.assign(node({manualRankPanel: String(i + 1)}), {hidden: i !== 0}));
    const group = {buttons, panels, querySelectorAll: selector => selector === '[data-manual-rank]' ? buttons : panels};
    buttons.forEach(button => { button.group = group; });
    detail.querySelectorAll = () => buttons;
    return group;
  });
  const listeners = new Map();
  const el = {contains: () => true, querySelectorAll: selector => selector === '[data-manual-pick]' ? choices : details,
    addEventListener: (type, listener) => listeners.set(type, listener), removeEventListener: type => listeners.delete(type)};
  const window = {innerWidth: width, matchMedia: () => ({matches: reduced})};
  const hook = {...vm.runInNewContext(source, {window}), el};
  hook.mounted();
  const click = control => listeners.get('click')({target: control, preventDefault() {}});
  const key = (control, key) => listeners.get('keydown')({target: control, key, preventDefault() {}, stopPropagation() {}});
  return {hook, choices, details, groups, listeners, click, key};
}

test('skill selection retains the selected rank, including returning from a shorter rank set', () => {
  const env = fixture();
  env.hook.pushEvent = () => assert.fail('reference browsing must stay in the browser');
  env.click(env.groups[0].buttons[3]);
  env.click(env.choices[1]);
  assert.equal(env.details[0].hidden, true);
  assert.equal(env.details[1].hidden, false);
  assert.equal(env.groups[1].panels[3].hidden, false);
  assert.equal(env.groups[1].buttons[3].getAttribute('aria-selected'), 'true');
  env.click(env.choices[2]);
  assert.equal(env.groups[2].panels[2].hidden, false);
  env.click(env.choices[0]);
  assert.equal(env.groups[0].panels[3].hidden, false);
});

test('avatar ultimates retain their rank independently of the skill reference', () => {
  const avatars = fixture({kind: 'avatar', levels: [3, 3, 3]}), skills = fixture();
  avatars.click(avatars.groups[0].buttons[2]);
  avatars.click(avatars.choices[1]);
  assert.equal(avatars.groups[1].panels[2].hidden, false);
  assert.equal(avatars.choices[1].getAttribute('aria-pressed'), 'true');
  assert.equal(skills.groups[0].panels[0].hidden, false);
  avatars.click(avatars.choices[2]);
  assert.equal(avatars.groups[2].panels[2].hidden, false);
});

test('rank keyboard navigation switches panels and updates the rank used for the next selection', () => {
  const env = fixture();
  env.click(env.groups[0].buttons[1]);
  env.key(env.groups[0].buttons[1], 'ArrowRight');
  assert.equal(env.groups[0].panels[2].hidden, false);
  assert.equal(env.groups[0].buttons[2].focused, true);
  env.click(env.choices[1]);
  assert.equal(env.groups[1].panels[2].hidden, false);
  env.key(env.groups[1].buttons[2], 'Home');
  assert.equal(env.groups[1].panels[0].hidden, false);
});

test('reduced motion skips animations and leaving the page removes listeners', () => {
  const env = fixture({reduced: true});
  env.click(env.choices[1]);
  assert.equal(env.hook.animations.size, 0);
  env.hook.destroyed();
  assert.equal(env.listeners.size, 0);
});

test('mobile selections bring the selected details into view', () => {
  const env = fixture({width: 390});
  env.click(env.choices[1]);
  assert.equal(env.details[1].scrolled, true);
});
