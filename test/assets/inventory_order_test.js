const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/inventory_order.js', 'utf8')
  .replace('export function ', 'function ').replace('export default InventoryOrder;', '({InventoryOrder, moveInventoryItem});');

function environment({columns = 3, statusId = 'hero-inventory-status', codes = ['boots', 'dagon', 'mask'], reducedMotion = false} = {}) {
  const classes = () => { const values = new Set(); return {add: name => values.add(name), remove: name => values.delete(name), has: name => values.has(name)}; };
  let items, hit, request, hidden = 0, requestedStatus;
  const listeners = new Map(), documentListeners = new Map(), captured = new Set(), status = {}, flying = [];
  const el = {id: statusId === 'shop-inventory-status' ? 'shop-inventory-order' : 'hero-inventory', dataset: {reorderable: 'true', heroId: '123', orderStatus: statusId}, classList: classes(),
    getBoundingClientRect: () => ({width: 400}),
    querySelectorAll: () => items, contains: item => items.includes(item),
    addEventListener: (type, fn) => listeners.set(type, fn), removeEventListener: type => listeners.delete(type),
    setPointerCapture: id => captured.add(id), hasPointerCapture: id => captured.has(id), releasePointerCapture: id => captured.delete(id)};
  const makeItem = (code, rarity = 'normal') => ({dataset: {itemCode: code, itemName: code, rarity}, classList: classes(),
    animate(frames, options) { this.animation = {frames, options, cancel() { this.cancelled = true; }}; return this.animation; },
    style: {removeProperty(name) { delete this[name]; }}, focus() { this.focused = true; },
    getBoundingClientRect() { return {left: items.indexOf(this) * 50, top: Math.floor(items.indexOf(this) / columns) * 50, width: 48, height: 48}; },
    querySelector() { return {src: `/items/${code}.png`}; },
    closest(selector) { return selector === '[data-item-code]' ? this : selector === '[data-inventory-order]' ? el : null; }});
  items = codes.map(code => makeItem(code));
  const document = {elementFromPoint: () => hit, getElementById: id => {
    if (id === 'shop-inventory-order') return el.id === id ? el : null;
    requestedStatus = id; return status;
  }, addEventListener: (type, listener) => documentListeners.set(type, listener), removeEventListener: type => documentListeners.delete(type),
  createElement: () => ({style: {}, setAttribute() {}, remove() { this.removed = true; }, animate(frames, options) { this.animation = {frames, options, cancel() { this.cancelled = true; }}; return this.animation; }}),
  body: {appendChild: image => flying.push(image)}};
  const {InventoryOrder} = vm.runInNewContext(source, {window: {matchMedia: () => ({matches: reducedMotion})}, document});
  const hook = {...InventoryOrder, el, hideTooltips: () => hidden++, pushEvent: (name, payload, callback) => {request = {name, payload, callback}; }};
  hook.mounted();
  const pointer = (type, item, x, y = 10) => listeners.get(type)({button: 0, isPrimary: true, pointerId: 1, target: item, clientX: x, clientY: y, preventDefault() {}});
  return {hook, el, listeners, documentListeners, flying, status, pointer,
    patch(codes, rarity = 'normal') { items = codes.map(code => items.find(item => item.dataset.itemCode === code) || makeItem(code, rarity)); hook.updated(); },
    items: () => items, hit: item => {hit = item;}, request: () => request, hidden: () => hidden, requestedStatus: () => requestedStatus,
    confirm() { items = request.payload.codes.map(code => items.find(item => item.dataset.itemCode === code)); hook.updated(); request.callback(); }
  };
}

test('pointer drag moves a passive item, persists all codes and restores focus after the patch', () => {
  const env = environment();
  const [boots,,mask] = env.items();
  env.pointer('pointerdown', boots, 10);
  env.hit(mask); env.pointer('pointermove', boots, 150);
  assert.equal(boots.classList.has('is-dragging'), true);
  assert.equal(mask.classList.has('is-drop-target'), true);
  assert.equal(env.hidden(), 1);
  env.pointer('pointerup', boots, 150);
  assert.equal(env.request().name, 'reorder-items');
  assert.equal(env.request().payload.hero_id, '123');
  assert.equal(env.request().payload.codes.join(), 'dagon,mask,boots');
  assert.equal(boots.classList.has('is-dragging'), false);
  env.confirm();
  assert.equal(env.items().at(-1), boots);
  assert.equal(boots.focused, true);
  assert.equal(env.status.textContent, 'boots moved to slot 3.');
  assert.equal(env.hook.pending, false);
});

test('the shop row uses its own status and a drag never triggers the inventory selection click', () => {
  const env = environment({statusId: 'shop-inventory-status', columns: 9});
  const first = env.items()[0];
  env.pointer('pointerdown', first, 10); env.hit(env.items()[2]); env.pointer('pointermove', first, 150); env.pointer('pointerup', first, 150);
  let prevented = 0, stopped = 0;
  const click = {preventDefault() { prevented++; }, stopPropagation() { stopped++; }};
  env.listeners.get('click')(click);
  assert.equal(prevented, 1); assert.equal(stopped, 1);
  env.listeners.get('click')(click);
  assert.equal(prevented, 1, 'ordinary clicks still select items');
  env.confirm();
  assert.equal(env.requestedStatus(), 'shop-inventory-status');
  assert.equal(env.status.textContent, 'boots moved to slot 3.');
});

test('keyboard row moves follow the actual inventory grid width', () => {
  const key = env => env.listeners.get('keydown')({altKey: true, key: 'ArrowDown', target: env.items()[0], preventDefault() {}, stopPropagation() {}});
  const codes = ['a', 'b', 'c', 'd', 'e', 'f'];
  const mobile = environment({columns: 3, codes});
  key(mobile); assert.equal(mobile.request().payload.codes.join(), 'b,c,d,a,e,f');
  const shop = environment({columns: 9, codes});
  key(shop); assert.equal(shop.request(), undefined, 'the desktop shop has only one inventory row');
});

test('a click, a cancelled drag and a drop outside inventory never save', () => {
  const env = environment(), boots = env.items()[0];
  env.pointer('pointerdown', boots, 10); env.pointer('pointermove', boots, 12); env.pointer('pointerup', boots, 12);
  assert.equal(env.request(), undefined);
  env.pointer('pointerdown', boots, 10); env.hit(env.items()[2]); env.pointer('pointermove', boots, 150);
  env.listeners.get('pointercancel')(); env.pointer('pointerup', boots, 150);
  assert.equal(env.request(), undefined);
  env.pointer('pointerdown', boots, 10); env.hit(null); env.pointer('pointermove', boots, 200); env.pointer('pointerup', boots, 200);
  assert.equal(env.request(), undefined);
});

test('Alt and arrow keys reorder one slot; editing, modifiers and boundaries are respected', () => {
  const env = environment();
  const key = options => env.listeners.get('keydown')({altKey: true, key: 'ArrowRight', target: env.items()[0], preventDefault() {}, stopPropagation() {}, ...options});
  env.el.dataset.reorderable = 'false'; key(); assert.equal(env.request(), undefined);
  env.el.dataset.reorderable = 'true'; key({ctrlKey: true}); assert.equal(env.request(), undefined);
  key({key: 'ArrowLeft'}); assert.equal(env.request(), undefined);
  key(); assert.equal(env.request().payload.codes.join(), 'dagon,boots,mask');
  env.confirm(); assert.equal(env.status.textContent, 'boots moved to slot 2.');
});

test('LiveView updates cancel an in-progress drag and destroying removes listeners', () => {
  const env = environment(), boots = env.items()[0];
  env.pointer('pointerdown', boots, 10); env.hit(env.items()[2]); env.pointer('pointermove', boots, 150);
  env.hook.updated(); env.pointer('pointerup', boots, 150);
  assert.equal(env.request(), undefined);
  assert.equal(boots.classList.has('is-dragging'), false);
  env.hook.destroyed(); assert.equal(env.listeners.size, 0);
});

test('purchases and transmutes animate only newly acquired items in their rarity colour', () => {
  const env = environment();
  assert.ok(env.items().every(item => !item.animation), 'initial inventory stays still');
  env.patch(['boots', 'dagon', 'mask', 'arcane_boots'], 'rare');
  const rare = env.items().at(-1);
  assert.match(rare.animation.frames[0].filter, /#8abde6/);
  assert.equal(rare.animation.options.duration, 1000);
  assert.ok(env.items().slice(0, 3).every(item => !item.animation));
  rare.animation.onfinish();
  assert.equal(env.hook.arrivals.size, 0);

  env.patch(['arcane_boots', 'octarine_core'], 'legendary');
  const legendary = env.items().at(-1);
  assert.match(legendary.animation.frames[0].filter, /#ec9a9e/);
  assert.equal(env.hook.arrivals.size, 1);
  env.patch(['octarine_core', 'arcane_boots']);
  assert.equal(env.items()[0].animation, legendary.animation, 'reordering does not restart the bloom');
  env.patch(['arcane_boots']);
  assert.equal(legendary.animation.cancelled, true, 'selling an arriving item stops its animation');
});

test('hero changes and reopening inventory do not celebrate existing equipment', () => {
  const env = environment();
  env.el.dataset.heroId = '456';
  env.patch(['new_hero_item'], 'epic');
  assert.equal(env.items()[0].animation, undefined);
  env.patch(['new_hero_item']);
  assert.equal(env.items()[0].animation, undefined);
});

test('reduced motion retains a short rarity glow without movement and teardown cancels it', () => {
  const env = environment({reducedMotion: true});
  env.patch(['boots', 'dagon', 'mask', 'bloodstone'], 'epic');
  const animation = env.items().at(-1).animation;
  assert.ok(animation.frames.every(frame => frame.transform === 'none'));
  assert.match(animation.frames[0].filter, /#bb9ae4/);
  assert.equal(animation.options.duration, 450);
  env.hook.destroyed();
  assert.equal(animation.cancelled, true);
  assert.equal(env.hook.arrivals.size, 0);
});

test('a confirmed purchase flies from its button to the hero bar before the landing glow', () => {
  const env = environment();
  const button = {dataset: {acquireCode: 'bloodstone', heroId: '123'}, getBoundingClientRect: () => ({left: 600, top: 400, width: 200, height: 50})};
  env.documentListeners.get('click')({target: {closest: () => button}});
  assert.equal(env.flying.length, 0, 'a click alone cannot celebrate a failed purchase');
  env.patch(['boots', 'dagon', 'mask', 'bloodstone'], 'epic');
  assert.equal(env.flying.length, 1);
  const image = env.flying[0];
  assert.equal(image.src, '/items/bloodstone.png');
  assert.match(image.animation.frames[0].transform, /translate\(676px, 401px\)/);
  assert.match(image.style.border, /#bb9ae4/);
  assert.equal(env.items().at(-1).animation.options.delay, 650);
  image.animation.onfinish();
  assert.equal(image.removed, true);
  assert.equal(env.hook.flights.size, 0);
});

test('the shop inventory pops immediately without launching a second transfer', () => {
  const env = environment({statusId: 'shop-inventory-status'});
  const button = {dataset: {acquireCode: 'bloodstone', heroId: '123'}, getBoundingClientRect: () => ({left: 600, top: 400, width: 200, height: 50})};
  env.documentListeners.get('click')({target: {closest: () => button}});
  env.patch(['boots', 'dagon', 'mask', 'bloodstone'], 'epic');
  assert.equal(env.flying.length, 0);
  assert.equal(env.items().at(-1).animation.options.delay, 0);
});

test('submitted transmutes transfer too; other heroes and reduced motion never launch a flight', () => {
  const env = environment();
  const button = {dataset: {acquireCode: 'arcane_boots', heroId: '123'}, getBoundingClientRect: () => ({left: 600, top: 400, width: 200, height: 50})};
  env.documentListeners.get('submit')({submitter: button});
  env.patch(['arcane_boots'], 'rare');
  assert.equal(env.flying.length, 1);
  env.hook.destroyed();
  assert.equal(env.flying[0].removed, true);
  assert.equal(env.flying[0].animation.cancelled, true);
  assert.equal(env.documentListeners.size, 0);

  const reduced = environment({reducedMotion: true});
  reduced.documentListeners.get('submit')({submitter: button});
  reduced.patch(['arcane_boots'], 'rare');
  assert.equal(reduced.flying.length, 0);
  assert.equal(reduced.items()[0].animation.options.delay, 0);

  const other = environment();
  other.documentListeners.get('submit')({submitter: {...button, dataset: {...button.dataset, heroId: '456'}}});
  other.patch(['arcane_boots'], 'rare');
  assert.equal(other.flying.length, 0);
});
