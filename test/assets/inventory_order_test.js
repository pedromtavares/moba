const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/inventory_order.js', 'utf8')
  .replace('export function ', 'function ').replace('export default InventoryOrder;', '({InventoryOrder, moveInventoryItem});');

function environment({columns = 3, statusId = 'hero-inventory-status', codes = ['boots', 'dagon', 'mask']} = {}) {
  const classes = () => { const values = new Set(); return {add: name => values.add(name), remove: name => values.delete(name), has: name => values.has(name)}; };
  let items, hit, request, hidden = 0, requestedStatus;
  const listeners = new Map(), captured = new Set(), status = {};
  const el = {dataset: {reorderable: 'true', heroId: '123', orderStatus: statusId}, classList: classes(),
    querySelectorAll: () => items, contains: item => items.includes(item),
    addEventListener: (type, fn) => listeners.set(type, fn), removeEventListener: type => listeners.delete(type),
    setPointerCapture: id => captured.add(id), hasPointerCapture: id => captured.has(id), releasePointerCapture: id => captured.delete(id)};
  items = codes.map(code => ({dataset: {itemCode: code, itemName: code}, classList: classes(),
    style: {removeProperty(name) { delete this[name]; }}, focus() { this.focused = true; },
    getBoundingClientRect() { return {top: Math.floor(items.indexOf(this) / columns) * 50}; },
    closest(selector) { return selector === '[data-item-code]' ? this : selector === '[data-inventory-order]' ? el : null; }}));
  const {InventoryOrder} = vm.runInNewContext(source, {document: {elementFromPoint: () => hit, getElementById: id => {requestedStatus = id; return status;}}});
  const hook = {...InventoryOrder, el, hideTooltips: () => hidden++, pushEvent: (name, payload, callback) => {request = {name, payload, callback}; }};
  hook.mounted();
  const pointer = (type, item, x, y = 10) => listeners.get(type)({button: 0, isPrimary: true, pointerId: 1, target: item, clientX: x, clientY: y, preventDefault() {}});
  return {hook, el, listeners, status, pointer,
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
