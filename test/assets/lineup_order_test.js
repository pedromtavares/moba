const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/lineup_order.js', 'utf8').replace('export default LineupOrder;', 'LineupOrder;');

function lineup() {
  let hit, request;
  const listeners = new Map();
  const captured = new Set();
  const cards = [1, 2, 3].map(id => ({dataset: {lineupHero: String(id)}}));
  const emptySlots = [{dataset: {}}, {dataset: {}}];
  const collectionHero = {dataset: {lineupAdd: '4'}};
  const document = {elementFromPoint: () => hit};
  const el = {
    dataset: {lineupId: '42'},
    addEventListener: (type, listener) => listeners.set(type, listener),
    querySelectorAll: () => cards,
    querySelector: selector => selector === '[data-lineup-empty]' ? emptySlots[0] : null,
    contains: card => cards.includes(card) || emptySlots.includes(card) || card === collectionHero,
    setPointerCapture: id => captured.add(id),
    hasPointerCapture: id => captured.has(id),
    releasePointerCapture: id => captured.delete(id)
  };
  const hook = {
    ...vm.runInNewContext(source, {document}),
    el,
    pushEvent: (name, payload) => { request = {name, payload}; }
  };
  hook.mounted();

  const inside = (card, isAction = false) => ({
    closest(selector) {
      if (selector === '[data-lineup-hero]') return cards.includes(card) ? card : null;
      if (selector === '[data-lineup-add]') return card === collectionHero ? card : null;
      if (selector === '[data-lineup-empty]') return emptySlots.includes(card) ? card : null;
      return isAction ? this : null;
    }
  });
  const pointer = (type, target, clientY, extra = {}) => listeners.get(type)({
    target, clientX: 10, clientY, pointerId: 1, isPrimary: true, button: 0, preventDefault() {}, ...extra
  });

  return {cards, emptySlots, collectionHero, inside, pointer, captured, hook, el, hit: target => { hit = target; }, request: () => request};
}

test('dragging from card content highlights only the current destination and saves its position', () => {
  const ui = lineup();
  const [first, second, third] = ui.cards;
  const art = ui.inside(first);

  ui.pointer('pointerdown', art, 10);
  ui.pointer('pointermove', art, 13);
  assert.equal(first.dataset.lineupDragging, undefined);
  assert.equal(ui.captured.size, 0);

  ui.hit(ui.inside(second));
  ui.pointer('pointermove', art, 40);
  assert.equal(first.dataset.lineupDragging, '');
  assert.equal(second.dataset.lineupDrop, '');
  assert.equal(ui.captured.size, 1);

  ui.pointer('lostpointercapture', art, 40);
  ui.hit(ui.inside(third));
  ui.pointer('pointermove', ui.el, 70);
  assert.equal(second.dataset.lineupDrop, undefined);
  assert.equal(third.dataset.lineupDrop, '');

  ui.pointer('pointerup', ui.el, 70);
  assert.equal(ui.request().name, 'reorder-lineup');
  assert.equal(ui.request().payload.lineup_id, 42);
  assert.equal(ui.request().payload.hero_ids.join(), '2,3,1');
  assert.equal(first.dataset.lineupDragging, undefined);
  assert.equal(third.dataset.lineupDrop, undefined);
  assert.equal(ui.captured.size, 0);
});

test('a collection drag highlights the next available position and saves only on an empty slot', () => {
  const ui = lineup();
  const source = ui.inside(ui.collectionHero, true);
  const [firstEmpty, laterEmpty] = ui.emptySlots;

  ui.pointer('pointerdown', source, 10);
  ui.hit(ui.inside(ui.cards[0]));
  ui.pointer('pointermove', source, 40);
  ui.pointer('pointerup', ui.el, 40);
  assert.equal(ui.request(), undefined);

  ui.pointer('pointerdown', source, 10);
  ui.hit(ui.inside(laterEmpty));
  ui.pointer('pointermove', source, 80);
  assert.equal(firstEmpty.dataset.lineupDrop, '');
  assert.equal(laterEmpty.dataset.lineupDrop, undefined);

  ui.pointer('pointerup', ui.el, 80);
  assert.equal(ui.request().name, 'add-hero');
  assert.equal(ui.request().payload.id, '4');
  assert.equal(ui.request().payload.lineup_id, 42);
  assert.equal(firstEmpty.dataset.lineupDrop, undefined);
});

test('Arena collection drops use the match picking event', () => {
  const ui = lineup();
  ui.el.dataset.lineupAddEvent = 'pick-hero';
  const source = ui.inside(ui.collectionHero, true);

  ui.pointer('pointerdown', source, 10);
  ui.hit(ui.inside(ui.emptySlots[0]));
  ui.pointer('pointermove', source, 40);
  ui.pointer('pointerup', ui.el, 40);

  assert.equal(ui.request().name, 'pick-hero');
  assert.equal(ui.request().payload.lineup_id, 42);
  assert.equal(ui.request().payload.id, '4');
});

test('card actions, cancelled drags, and drops outside the lineup leave the order alone', () => {
  const ui = lineup();
  const [first, second] = ui.cards;
  const body = ui.inside(first);
  const action = ui.inside(first, true);

  ui.hit(ui.inside(second));
  ui.pointer('pointerdown', action, 10);
  ui.pointer('pointermove', action, 40);
  ui.pointer('pointerup', action, 40);
  assert.equal(ui.request(), undefined);

  ui.pointer('pointerdown', body, 10);
  ui.pointer('pointermove', body, 40);
  assert.equal(second.dataset.lineupDrop, '');
  ui.hook.updated();
  assert.equal(second.dataset.lineupDrop, undefined);
  ui.pointer('pointerup', body, 40);
  assert.equal(ui.request(), undefined);

  ui.pointer('pointerdown', body, 10);
  ui.pointer('pointermove', body, 40);
  ui.hit(null);
  ui.pointer('pointerup', body, 80);
  assert.equal(second.dataset.lineupDrop, undefined);
  assert.equal(ui.request(), undefined);
});
