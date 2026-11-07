const LineupOrder = {
  mounted() {
    this.listeners = {
      pointerdown: event => this.startDrag(event),
      pointermove: event => this.moveDrag(event),
      pointerup: event => this.finishDrag(event),
      pointercancel: () => this.cancelDrag(),
      pointerleave: () => {
        if (!this.drag?.active) this.cancelDrag();
      },
      lostpointercapture: event => {
        if (event.target === this.el) this.cancelDrag();
      },
      dragstart: event => {
        if (this.drag) event.preventDefault();
      },
      keydown: event => this.moveWithKeyboard(event)
    };

    for (const [type, listener] of Object.entries(this.listeners)) {
      this.el.addEventListener(type, listener);
    }
  },

  updated() {
    this.cancelDrag();
  },

  destroyed() {
    this.cancelDrag();
    for (const [type, listener] of Object.entries(this.listeners)) {
      this.el.removeEventListener(type, listener);
    }
  },

  rows() {
    return [...this.el.querySelectorAll('[data-lineup-hero]')];
  },

  startDrag(event) {
    if (!this.el.dataset.lineupId || this.pending || this.drag || event.button !== 0 || !event.isPrimary) return;

    const collectionHero = event.target.closest('[data-lineup-add]');
    if (!collectionHero &&
        event.target.closest('a, button:not([data-lineup-grip]), input, select, textarea')) return;

    const source = collectionHero || event.target.closest('[data-lineup-hero]');
    if (!source || !this.el.contains(source)) return;
    if (!collectionHero && this.rows().length < 2) return;

    this.drag = {
      pointer: event.pointerId,
      lineupId: this.el.dataset.lineupId,
      source,
      adding: Boolean(collectionHero),
      x: event.clientX,
      y: event.clientY,
      target: null,
      active: false
    };
  },

  moveDrag(event) {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointer) return;
    if (!drag.active) {
      if (Math.hypot(event.clientX - drag.x, event.clientY - drag.y) < 6) return;

      drag.active = true;
      drag.source.dataset.lineupDragging = '';
      this.hideTooltips?.();
      this.el.setPointerCapture(drag.pointer);
    }

    event.preventDefault();
    this.highlightTarget(event);
  },

  highlightTarget(event) {
    const drag = this.drag;
    const selector = drag.adding ? '[data-lineup-empty]' : '[data-lineup-hero]';
    const hit = document.elementFromPoint(event.clientX, event.clientY)?.closest(selector);
    let target = hit && hit !== drag.source && this.el.contains(hit) ? hit : null;
    if (target && drag.adding) target = this.el.querySelector(selector);
    if (drag.target === target) return;

    if (drag.target) delete drag.target.dataset.lineupDrop;
    drag.target = target;
    if (target) target.dataset.lineupDrop = '';
  },

  finishDrag(event) {
    if (!this.drag || event.pointerId !== this.drag.pointer) return;
    if (this.drag.active) this.highlightTarget(event);
    const {source, target, adding, lineupId} = this.drag;
    this.cancelDrag();
    if (!target || lineupId !== this.el.dataset.lineupId) return;

    if (adding) {
      this.pending = true;
      const eventName = this.el.dataset.lineupAddEvent || 'add-hero';
      this.pushEvent(eventName, {id: source.dataset.lineupAdd, lineup_id: Number(lineupId)}, () => {
        this.pending = false;
      });
    } else {
      this.saveOrder(source, target);
    }
  },

  cancelDrag() {
    const drag = this.drag;
    if (!drag) return;
    this.drag = null;
    delete drag.source.dataset.lineupDragging;
    if (drag.target) delete drag.target.dataset.lineupDrop;
    if (this.el.hasPointerCapture(drag.pointer)) this.el.releasePointerCapture(drag.pointer);
  },

  moveWithKeyboard(event) {
    const grip = event.target.closest('[data-lineup-grip]');
    if (!grip || !this.el.dataset.lineupId || this.pending || this.drag ||
        event.altKey || event.ctrlKey || event.metaKey || event.shiftKey ||
        !['ArrowUp', 'ArrowDown'].includes(event.key)) return;

    event.preventDefault();
    const rows = this.rows();
    const source = grip.closest('[data-lineup-hero]');
    const offset = event.key === 'ArrowUp' ? -1 : 1;
    const target = rows[rows.indexOf(source) + offset];
    if (target) this.saveOrder(source, target, true);
  },

  saveOrder(source, target, restoreFocus = false) {
    const rows = this.rows();
    const from = rows.indexOf(source);
    const to = rows.indexOf(target);
    const lineupId = this.el.dataset.lineupId;
    if (!lineupId || from < 0 || to < 0 || from === to) return;
    const heroIds = rows.map(row => Number(row.dataset.lineupHero));
    heroIds.splice(to, 0, ...heroIds.splice(from, 1));

    this.pending = true;
    this.pushEvent('reorder-lineup', {lineup_id: Number(lineupId), hero_ids: heroIds}, () => {
      this.pending = false;
      if (restoreFocus && this.el.dataset.lineupId === lineupId && source.isConnected) {
        source.querySelector('[data-lineup-grip]')?.focus({preventScroll: true});
      }
    });
  }
};

export default LineupOrder;
