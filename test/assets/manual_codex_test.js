const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/manual_codex.js', 'utf8').replace('export default ManualCodex;', 'ManualCodex;');

function fixture({reduced = false, kind = 'skill', levels = [5, 5, 3]} = {}) {
  function node(dataset = {}) {
    const attributes = new Map();
    return {dataset, hidden: false,
      setAttribute: (key, value) => attributes.set(key, value), getAttribute: key => attributes.get(key),
      hasAttribute(key) { return attributes.has(key); },
      focus() { this.focused = true; },
      closest(selector) {
        if (selector === '[data-manual-ranked]') return this.group;
        if (selector === '.manual-reference-section') return this.panel;
        return this;
      },
      animate() { return {cancel() { this.cancelled = true; }}; }};
  }
  const codes = kind === 'avatar' ? ['juggernaut', 'axe', 'lina'] : ['blink_strike', 'empower', 'decay'];
  const choices = codes.map(code => node({manualPick: kind, code}));
  choices.forEach((choice, index) => choice.setAttribute('aria-pressed', String(index === 0)));
  const details = codes.map((code, index) => Object.assign(node({manualDetail: kind, code}), {hidden: index !== 0}));
  if (kind === 'item') {
    details[0].dataset.rarity = 'normal';
    details[1].dataset.rarity = details[2].dataset.rarity = 'rare';
    choices.push(node({manualPick: 'item-category', manualRarity: 'normal', code: codes[0]}));
    choices.push(node({manualPick: 'item-category', manualRarity: 'rare', code: codes[1]}));
  }
  const itemDetailsView = {checked: false};
  const panels = ['avatars', 'skills', 'items'].map((id, index) => ({
    id: 'manual-' + id,
    hidden: index !== 0,
    querySelector: selector => id === 'items' && selector === '#manual-item-view-details' ? itemDetailsView : null,
    querySelectorAll: selector => selector === '[data-manual-pick]' ? choices : details
  }));
  const contentPanel = panels[{avatar: 0, skill: 1, item: 2}[kind]];
  choices.forEach(choice => { choice.panel = contentPanel; });
  const tabs = panels.map((panel, index) => {
    const tab = node();
    tab.setAttribute('data-library-tab', '');
    tab.setAttribute('aria-controls', panel.id);
    tab.setAttribute('aria-selected', String(index === 0));
    panel.animate = tab.animate;
    return tab;
  });
  const groups = details.map((detail, index) => {
    const buttons = Array.from({length: levels[index]}, (_, i) => node({manualRank: String(i + 1)}));
    const panels = Array.from({length: levels[index]}, (_, i) => Object.assign(node({manualRankPanel: String(i + 1)}), {hidden: i !== 0}));
    const group = {buttons, panels, querySelectorAll: selector => selector === '[data-manual-rank]' ? buttons : panels};
    buttons.forEach(button => { button.group = group; button.panel = contentPanel; });
    detail.querySelectorAll = () => buttons;
    return group;
  });
  const listeners = new Map();
  const el = {contains: () => true, querySelectorAll: () => tabs, querySelector: selector => panels.find(panel => '#' + panel.id === selector),
    addEventListener: (type, listener) => listeners.set(type, listener), removeEventListener: type => listeners.delete(type)};
  const window = {matchMedia: () => ({matches: reduced})};
  const hook = {...vm.runInNewContext(source, {window}), el};
  hook.mounted();
  const click = control => listeners.get('click')({target: control, preventDefault() {}});
  const key = (control, key) => listeners.get('keydown')({target: control, key, preventDefault() {}, stopPropagation() {}});
  return {hook, choices, details, groups, tabs, panels, listeners, click, key, itemDetailsView};
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

test('Library tabs switch locally, wrap with arrow keys, and preserve selections', () => {
  const env = fixture();
  env.click(env.groups[0].buttons[2]);
  env.click(env.choices[1]);
  env.click(env.tabs[1]);
  assert.deepEqual(env.panels.map(panel => panel.hidden), [true, false, true]);
  env.key(env.tabs[1], 'End');
  assert.deepEqual(env.panels.map(panel => panel.hidden), [true, true, false]);
  assert.equal(env.tabs[2].focused, true);
  env.key(env.tabs[2], 'ArrowRight');
  assert.deepEqual(env.panels.map(panel => panel.hidden), [false, true, true]);
  env.key(env.tabs[0], 'ArrowRight');
  assert.equal(env.tabs[1].tabIndex, 0);
  assert.equal(env.details[1].hidden, false);
  assert.equal(env.groups[1].panels[2].hidden, false);
});

test('selecting a shop shelf or item highlights the correct rarity and shows its details', () => {
  const env = fixture({kind: 'item', levels: [0, 0, 0]});
  const [normal, firstRare, secondRare, normalShelf, rareShelf] = env.choices;

  env.click(rareShelf);
  assert.equal(env.itemDetailsView.checked, false);
  assert.equal(env.details[1].hidden, false);
  assert.equal(firstRare.getAttribute('aria-pressed'), 'true');

  env.click(secondRare);
  assert.equal(env.itemDetailsView.checked, true);
  assert.equal(env.details[1].hidden, true);
  assert.equal(env.details[2].hidden, false);
  assert.equal(rareShelf.getAttribute('aria-pressed'), 'true');
  assert.equal(firstRare.getAttribute('aria-pressed'), 'false');

  env.click(normalShelf);
  assert.equal(env.details[0].hidden, false);
  assert.equal(normal.getAttribute('aria-pressed'), 'true');
  assert.equal(rareShelf.getAttribute('aria-pressed'), 'false');
});
