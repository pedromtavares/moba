const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/training_controls.js', 'utf8')
  .replace('export function initTrainingControls', 'function initTrainingControls') + '\ninitTrainingControls(requestFullscreen);';

function environment() {
  const listeners = {};
  const state = {hero: '1', battle: false, dialogs: [], fullscreen: 0, selection: ''};
  const control = () => ({
    clicks: 0, visible: true, disabled: false,
    getClientRects() { return this.visible ? [{}] : []; },
    getAttribute() { return null; },
    click() { this.clicks++; }, focus() { state.focused = this; }
  });
  state.heroes = [control(), control(), control()];
  state.skills = [control(), control(), control(), control()];
  state.shop = control();
  state.smallShop = control(); state.smallShop.visible = false;
  state.challenge = control(); state.challenge.visible = false;
  state.skillGuides = [];
  state.cards = [1, 2, 3].map(id => {
    const classes = new Set();
    return {id: `target-${id}`, button: control(), classes,
      classList: {toggle: (name, enabled) => enabled ? classes.add(name) : classes.delete(name)},
      querySelector() { return this.button; }
    };
  });
  state.hud = control();
  state.hud.querySelector = selector => selector === '[data-inventory-order]' ? {dataset: {heroId: state.hero}} :
    selector === '.shop-modal.d-block' ? state.openShop : state.skills[selector.match(/index="(\d)"/)?.[1]];
  state.hud.querySelectorAll = () => [state.shop, state.smallShop];
  const document = {
    addEventListener: (name, handler) => { listeners[name] = handler; },
    querySelector: selector => {
      if (selector === '.game-page #hero-bar') return state.hud;
      if (selector === '#battle-page') return state.battle;
      if (selector === '#hero-inventory') return {dataset: {heroId: state.hero}};
      if (selector === '.training #start-league-challenge') return state.challenge;
      return state.heroes[Number(selector.match(/team-select-(\d)/)?.[1]) - 1];
    },
    querySelectorAll: selector => {
      if (selector === '.game-page .training-target') return state.cards;
      if (selector === '.game-page .hero-bar') return [state.hud];
      if (selector === '.training .ascent-challenge') return [state.challenge];
      if (selector === '.training .league-skill-warning') return state.skillGuides;
      return state.dialogs;
    }
  };
  vm.runInNewContext(source, {requestAnimationFrame: callback => callback(), document, requestFullscreen: () => state.fullscreen++, window: {
    addEventListener: (name, handler) => { listeners[name] = handler; },
    getSelection: () => ({toString: () => state.selection})
  }});
  state.press = (key, options = {}) => {
    const event = {key, code: key === ' ' ? 'Space' : key, defaultPrevented: false,
      target: {closest: () => null}, preventDefault() { this.defaultPrevented = true; }, ...options};
    listeners.keydown(event); return event;
  };
  state.clickCard = (index, interactive = false) => {
    const event = {button: 0, target: {closest: selector => selector === '.game-page .training-target' ? state.cards[index] : interactive ? {} : null},
      preventDefault() { this.defaultPrevented = true; }};
    listeners.click(event); return event;
  };
  state.refresh = listeners['phx:update'];
  state.switchHero = listeners['team:hero-switched'];
  state.selected = () => state.cards.findIndex(card => card.classes.has('is-keyboard-selected'));
  return state;
}

test('1–3 switch heroes, QWER level their displayed skills, and F opens the visible shop control', () => {
  const page = environment();
  for (const key of ['1', '2', '3', 'q', 'w', 'e', 'r', 'f']) assert.equal(page.press(key).defaultPrevented, true);
  assert.deepEqual(page.heroes.map(button => button.clicks), [1, 1, 1]);
  assert.deepEqual(page.skills.map(button => button.clicks), [1, 1, 1, 1]);
  assert.equal(page.shop.clicks, 1);
  page.shop.visible = false; page.smallShop.visible = true;
  page.press('f'); assert.equal(page.smallShop.clicks, 1);
  page.skills[0] = null;
  assert.equal(page.press('q').defaultPrevented, false);
});

test('arrows select and focus targets, wrap around, and Space launches exactly the selected battle', () => {
  const page = environment();
  assert.equal(page.selected(), 0);
  page.press('ArrowRight'); assert.equal(page.selected(), 1);
  assert.equal(page.focused, page.cards[1].button);
  page.press(' '); assert.equal(page.cards[1].button.clicks, 1);
  assert.equal(page.fullscreen, 1);
  page.press('ArrowLeft'); page.press('ArrowUp'); assert.equal(page.selected(), 2);
  page.press('ArrowDown'); assert.equal(page.selected(), 0);
  page.hero = '2'; page.refresh(); assert.equal(page.selected(), 0);
  page.cards[0].button.disabled = true;
  page.refresh(); assert.equal(page.selected(), 1);
});

test('whole-card clicks reuse Battle without duplicating button clicks or text selection', () => {
  const page = environment();
  page.clickCard(2); assert.equal(page.cards[2].button.clicks, 1);
  assert.equal(page.selected(), 2);
  page.clickCard(2, true); assert.equal(page.cards[2].button.clicks, 1);
  page.selection = 'Copied skill name';
  page.clickCard(1); assert.equal(page.cards[1].button.clicks, 0);
});

test('typing, dialogs, unavailable HUDs, battle item keys, modifiers and held keys are protected', () => {
  const page = environment();
  for (const options of [{repeat: true}, {isComposing: true}, {ctrlKey: true}, {metaKey: true}, {altKey: true}, {shiftKey: true}, {defaultPrevented: true}, {target: {closest: () => ({})}}]) page.press('1', options);
  page.dialogs = [{getClientRects: () => [{}]}]; page.press('1'); page.press(' ');
  page.dialogs = []; page.battle = true; page.press('1');
  page.battle = false; page.hud.visible = false; page.press('1');
  assert.equal(page.heroes[0].clicks, 0);
  assert.equal(page.cards[0].button.clicks, 0);
});

test('Space starts the league challenge when target cards are gone, and respects native focused buttons', () => {
  const page = environment();
  page.cards = []; page.challenge.visible = true;
  page.press(' '); assert.equal(page.challenge.clicks, 1);
  page.press(' ', {target: {closest: selector => selector.startsWith('button') ? {} : null}});
  assert.equal(page.challenge.clicks, 1);
});

test('Space activates only the visible skill guide without launching a battle', () => {
  const page = environment();
  const hidden = {...page.challenge};
  const guide = {...page.challenge, visible: true};
  page.skillGuides = [hidden, guide];
  page.cards = [];
  page.challenge.visible = true;
  assert.equal(page.press(' ').defaultPrevented, true);
  assert.equal(guide.clicks, 1);
  assert.equal(hidden.clicks, 0);
  assert.equal(page.challenge.clicks, 0);
  assert.equal(page.fullscreen, 0);

  const focused = {closest: selector => selector.startsWith('button') ? guide : null};
  assert.equal(page.press(' ', {target: focused}).defaultPrevented, false);
  assert.equal(guide.clicks, 1);
});

test('preloaded hidden HUDs and target cards never receive actions after switching heroes locally', () => {
  const page = environment();
  page.press('ArrowRight');
  page.cards[0].button.visible = false;
  page.cards[1].button.visible = false;
  page.hero = '3';
  page.switchHero();
  assert.equal(page.selected(), 2);
  page.press(' ');
  assert.equal(page.cards[2].button.clicks, 1);
  assert.equal(page.cards[0].button.clicks, 0);
});

test('1–3 switch heroes through an open shop, with focus on the new inventory and other shortcuts blocked', () => {
  const page = environment();
  const selection = {focus() { page.focused = this; }};
  const shop = {getClientRects: () => [{}], classList: {contains: name => name === 'shop-modal'}, querySelector: () => selection};
  page.dialogs = [shop]; page.openShop = shop;
  for (const key of ['1', '2', '3']) assert.equal(page.press(key).defaultPrevented, true);
  assert.deepEqual(page.heroes.map(button => button.clicks), [1, 1, 1]);
  for (const key of ['q', 'f', ' ', 'ArrowRight']) assert.equal(page.press(key).defaultPrevented, false);
  assert.equal(page.skills[0].clicks, 0);
  assert.equal(page.cards[0].button.clicks, 0);
  page.hero = '2'; page.switchHero();
  assert.equal(page.focused, selection);
  assert.equal(page.openShop, shop);
  const clicks = page.heroes[1].clicks;
  for (const options of [{repeat: true}, {ctrlKey: true}, {target: {closest: () => ({})}}]) page.press('2', options);
  page.dialogs.push({getClientRects: () => [{}]});
  page.press('2');
  assert.equal(page.heroes[1].clicks, clicks);
});
