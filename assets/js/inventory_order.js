export function moveInventoryItem(codes, from, to) {
  if (from < 0 || to < 0 || from >= codes.length || to >= codes.length) return codes;
  const result = [...codes];
  result.splice(to, 0, ...result.splice(from, 1));
  return result;
}

const InventoryOrder = {
  mounted() {
    this.disposed = false;
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
  },
  updated() { this.cancelDrag(); },
  destroyed() {
    this.disposed = true;
    this.cancelDrag();
    Object.entries(this.listeners).forEach(([type, listener]) => this.el.removeEventListener(type, listener));
  },
  items() { return [...this.el.querySelectorAll('[data-item-code]')]; },
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
