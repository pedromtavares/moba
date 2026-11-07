export function moveInventoryItem(codes, from, to) {
  if (from < 0 || to < 0 || from >= codes.length || to >= codes.length) return codes;
  const result = [...codes];
  result.splice(to, 0, ...result.splice(from, 1));
  return result;
}

const InventoryOrder = {
  mounted() {
    this.disposed = false;
    this.arrivals = new Map();
    this.flights = new Set();
    this.inventoryHero = this.el.dataset.heroId;
    this.inventoryCodes = new Set(this.items().map(item => item.dataset.itemCode));
    this.listeners = {
      pointerdown: event => this.startPointer(event),
      pointermove: event => this.movePointer(event),
      pointerup: event => this.finishPointer(event),
      pointercancel: () => this.cancelDrag(),
      lostpointercapture: () => this.cancelDrag(),
      keydown: event => this.moveWithKeyboard(event),
      click: event => {
        if (this.suppressClick) { event.preventDefault(); event.stopPropagation(); this.suppressClick = false; }
      }
    };
    Object.entries(this.listeners).forEach(([type, listener]) => this.el.addEventListener(type, listener));
    this.acquireListener = event => this.captureAcquisition(event);
    document.addEventListener('click', this.acquireListener, true);
    document.addEventListener('submit', this.acquireListener, true);
  },
  updated() {
    this.cancelDrag();
    const items = this.items();
    const sameHero = this.inventoryHero === this.el.dataset.heroId;
    this.arrivals.forEach((animation, item) => {
      if (!sameHero || !items.includes(item)) { animation.cancel(); this.arrivals.delete(item); }
    });
    if (sameHero) items.filter(item => !this.inventoryCodes.has(item.dataset.itemCode)).forEach(item => this.animateArrival(item));
    this.inventoryHero = this.el.dataset.heroId;
    this.inventoryCodes = new Set(items.map(item => item.dataset.itemCode));
  },
  destroyed() {
    this.disposed = true;
    this.arrivals.forEach(animation => animation.cancel());
    this.arrivals.clear();
    this.flights.forEach(flight => { flight.animation.cancel(); flight.image.remove(); });
    this.flights.clear();
    document.removeEventListener('click', this.acquireListener, true);
    document.removeEventListener('submit', this.acquireListener, true);
    this.cancelDrag();
    Object.entries(this.listeners).forEach(([type, listener]) => this.el.removeEventListener(type, listener));
  },
  items() { return [...this.el.querySelectorAll('[data-item-code]')]; },
  captureAcquisition(event) {
    const button = event.submitter || event.target.closest('[data-acquire-code]');
    if (!button?.dataset.acquireCode || button.disabled || button.dataset.heroId !== this.el.dataset.heroId) return;
    this.acquisition = {code: button.dataset.acquireCode, hero: button.dataset.heroId, rect: button.getBoundingClientRect(), time: Date.now()};
  },
  flyToInventory(item, source, color) {
    const target = item.getBoundingClientRect();
    const image = document.createElement('img');
    image.src = item.querySelector('img').src;
    image.alt = '';
    image.setAttribute('aria-hidden', 'true');
    const size = Math.min(64, Math.max(40, target.width));
    Object.assign(image.style, {position: 'fixed', left: '0', top: '0', width: `${size}px`, height: `${size}px`, objectFit: 'cover',
      borderRadius: '7px', border: `2px solid ${color}`, boxShadow: `0 0 24px ${color}`, pointerEvents: 'none', zIndex: '2147483646'});
    document.body.appendChild(image);
    const x = source.left + source.width / 2 - size / 2, y = source.top + source.height / 2 - size / 2;
    const endX = target.left + target.width / 2 - size / 2, endY = target.top + target.height / 2 - size / 2;
    const animation = image.animate([
      {offset: 0, opacity: .3, transform: `translate(${x}px, ${y}px) scale(.4)`, filter: 'brightness(2)'},
      {offset: .3, opacity: 1, transform: `translate(${x + (endX - x) * .25}px, ${Math.min(y, endY) - 45}px) scale(1.08)`, filter: 'brightness(1.3)'},
      {offset: 1, opacity: .8, transform: `translate(${endX}px, ${endY}px) scale(${target.width / size})`, filter: 'brightness(1.6)'}
    ], {duration: 650, easing: 'cubic-bezier(.3,0,.25,1)'});
    const flight = {image, animation};
    this.flights.add(flight);
    animation.onfinish = () => { image.remove(); this.flights.delete(flight); };
  },
  animateArrival(item) {
    const color = {normal: '#b8c4d2', rare: '#8abde6', epic: '#bb9ae4', legendary: '#ec9a9e'}[item.dataset.rarity] || '#b8c4d2';
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const source = this.acquisition;
    this.acquisition = null;
    const transfer = this.el.classList.contains('hud-inventory-items') && !reduced && source?.code === item.dataset.itemCode &&
      source.hero === this.el.dataset.heroId && Date.now() - source.time < 5000 && item.getBoundingClientRect().width > 0;
    if (transfer) this.flyToInventory(item, source.rect, color);
    const animation = item.animate([
      {offset: 0, opacity: transfer ? 0 : 1, transform: reduced ? 'none' : 'translateY(8px) scale(.7)', filter: `brightness(1.8) drop-shadow(0 0 16px ${color})`},
      {offset: .3, opacity: 1, transform: reduced ? 'none' : 'translateY(-2px) scale(1.12)', filter: `brightness(1.35) drop-shadow(0 0 12px ${color})`},
      {offset: 1, transform: 'none', filter: 'brightness(1) drop-shadow(0 0 0 transparent)'}
    ], {duration: reduced ? 450 : 1000, delay: transfer ? 650 : 0, fill: 'backwards', easing: 'cubic-bezier(.2,.7,.2,1)'});
    this.arrivals.set(item, animation);
    animation.onfinish = () => this.arrivals.delete(item);
  },
  enabled() { return this.el.dataset.reorderable === 'true' && !this.pending && this.items().length > 1; },
  startPointer(event) {
    if (!this.enabled() || event.button !== 0 || event.isPrimary === false || event.target.closest('select, input')) return;
    const item = event.target.closest('[data-item-code]');
    if (!item || !this.el.contains(item)) return;
    this.suppressClick = false;
    this.drag = {item, x: event.clientX, y: event.clientY, pointer: event.pointerId, target: null, active: false};
  },
  movePointer(event) {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointer) return;
    const x = event.clientX - drag.x, y = event.clientY - drag.y;
    if (!drag.active && Math.hypot(x, y) < 6) return;
    if (!drag.active) {
      drag.active = true;
      this.arrivals.get(drag.item)?.cancel();
      this.arrivals.delete(drag.item);
      this.hideTooltips?.();
      drag.item.classList.add('is-dragging');
      this.el.setPointerCapture(drag.pointer);
    }
    event.preventDefault();
    drag.item.style.transform = `translate(${x}px, ${y}px) scale(1.06)`;
    const hit = document.elementFromPoint(event.clientX, event.clientY);
    let target = hit?.closest('[data-item-code]');
    if (!target && hit?.closest('[data-inventory-order]') === this.el) target = this.items().at(-1);
    if (target === drag.item || !target || !this.el.contains(target)) target = null;
    drag.target?.classList.remove('is-drop-target');
    drag.target = target;
    target?.classList.add('is-drop-target');
  },
  finishPointer(event) {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointer) return;
    const items = this.items();
    const from = items.indexOf(drag.item), to = items.indexOf(drag.target);
    const moved = drag.active && from !== to && to >= 0;
    this.suppressClick = drag.active;
    this.cancelDrag();
    if (moved) this.saveOrder(items, from, to);
  },
  cancelDrag() {
    const drag = this.drag;
    this.drag = null;
    if (!drag) return;
    drag.item.classList.remove('is-dragging');
    drag.item.style.removeProperty('transform');
    drag.target?.classList.remove('is-drop-target');
    if (this.el.hasPointerCapture(drag.pointer)) this.el.releasePointerCapture(drag.pointer);
  },
  moveWithKeyboard(event) {
    if (!this.enabled() || !event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    const item = event.target.closest('[data-item-code]');
    if (!item) return;
    const items = this.items();
    const vertical = event.key === 'ArrowUp' || event.key === 'ArrowDown';
    const columns = vertical ? items.filter(item => Math.abs(item.getBoundingClientRect().top - items[0].getBoundingClientRect().top) < 1).length : 1;
    const offset = {ArrowLeft: -1, ArrowRight: 1, ArrowUp: -columns, ArrowDown: columns}[event.key];
    if (!offset) return;
    const from = items.indexOf(item), to = from + offset;
    if (to < 0 || to >= items.length) return;
    event.preventDefault();
    event.stopPropagation();
    this.hideTooltips?.();
    this.saveOrder(items, from, to);
  },
  saveOrder(items, from, to) {
    const codes = moveInventoryItem(items.map(item => item.dataset.itemCode), from, to);
    const code = items[from].dataset.itemCode, name = items[from].dataset.itemName;
    const heroId = this.el.dataset.heroId;
    this.pending = true;
    this.el.classList.add('is-saving');
    this.pushEvent('reorder-items', {hero_id: heroId, codes}, () => {
      if (this.disposed) return;
      this.pending = false;
      this.el.classList.remove('is-saving');
      if (this.el.dataset.heroId !== heroId) return;
      const ordered = this.items();
      const item = ordered.find(item => item.dataset.itemCode === code);
      item?.focus({preventScroll: true});
      const status = document.getElementById(this.el.dataset.orderStatus || 'hero-inventory-status');
      if (status) status.textContent = ordered.map(item => item.dataset.itemCode).join() === codes.join()
        ? `${name} moved to slot ${to + 1}.` : 'Your inventory changed. Try reordering again.';
    });
  }
};

export default InventoryOrder;
