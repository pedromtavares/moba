const navigationKeys = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End'];

const ManualCodex = {
  mounted() {
    this.tabs = [...this.el.querySelectorAll('[data-library-tab]')];
    this.animations = new Set();
    this.selectedRanks = new Map();
    this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.select = event => {
      const control = event.target.closest('[data-library-tab], [data-manual-pick], [data-manual-rank]');
      if (!control || !this.el.contains(control)) return;
      if (control.hasAttribute('data-library-tab')) this.tab(control);
      else if (control.dataset.manualPick) this.pick(control);
      else this.rank(control);
      event.preventDefault();
    };
    this.keyboard = event => {
      if (event.altKey || event.ctrlKey || event.metaKey || !navigationKeys.includes(event.key)) return;
      const control = event.target;
      if (control.hasAttribute('data-library-tab')) {
        if (['ArrowUp', 'ArrowDown'].includes(event.key)) return;
        this.move(event, this.tabs, tab => this.tab(tab));
      } else if (control.dataset.manualRank) {
        const ranks = [...control.closest('[data-manual-ranked]').querySelectorAll('[data-manual-rank]')];
        this.move(event, ranks, rank => this.rank(rank));
      }
    };
    this.el.addEventListener('click', this.select);
    this.el.addEventListener('keydown', this.keyboard);
  },
  move(event, controls, activate) {
    const index = controls.indexOf(event.target);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? controls.length - 1 :
      (index + (['ArrowUp', 'ArrowLeft'].includes(event.key) ? -1 : 1) + controls.length) % controls.length;
    event.preventDefault();
    event.stopPropagation();
    activate(controls[next]);
    controls[next].focus({preventScroll: true});
  },
  tab(button) {
    if (button.getAttribute('aria-selected') === 'true') return;
    this.hideTooltips?.();
    this.tabs.forEach(tab => {
      const selected = tab === button;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      this.el.querySelector('#' + tab.getAttribute('aria-controls')).hidden = !selected;
    });
    this.reveal(this.el.querySelector('#' + button.getAttribute('aria-controls')));
  },
  pick(button) {
    const panel = button.closest('.manual-reference-section');
    const details = [...panel.querySelectorAll('[data-manual-detail]')];
    const detail = details.find(entry => entry.dataset.code === button.dataset.code);
    if (!detail) return;
    this.hideTooltips?.();
    details.forEach(entry => { entry.hidden = entry !== detail; });
    panel.querySelectorAll('[data-manual-pick]').forEach(choice => {
      const selected = choice.dataset.manualRarity ?
        choice.dataset.manualRarity === detail.dataset.rarity : choice.dataset.code === detail.dataset.code;
      choice.setAttribute('aria-pressed', String(selected));
    });
    const ranks = [...detail.querySelectorAll('[data-manual-rank]')];
    const rank = ranks.find(button => Number(button.dataset.manualRank) === (this.selectedRanks.get(panel) ?? 1)) || ranks.at(-1);
    if (rank) this.rank(rank, false);
    if (button.dataset.manualPick === 'item') {
      const detailsView = panel.querySelector('#manual-item-view-details');
      if (detailsView) detailsView.checked = true;
    }
    this.reveal(detail);
  },
  rank(button, remember = true) {
    if (remember) this.selectedRanks.set(button.closest('.manual-reference-section'), Number(button.dataset.manualRank));
    const group = button.closest('[data-manual-ranked]');
    group.querySelectorAll('[data-manual-rank]').forEach(control => {
      control.setAttribute('aria-selected', String(control === button));
      control.tabIndex = control === button ? 0 : -1;
    });
    group.querySelectorAll('[data-manual-rank-panel]').forEach(panel => {
      panel.hidden = panel.dataset.manualRankPanel !== button.dataset.manualRank;
      if (!panel.hidden) this.reveal(panel);
    });
  },
  reveal(element) {
    this.animations.forEach(animation => animation.cancel());
    this.animations.clear();
    if (this.reducedMotion) return;
    const animation = element.animate([{opacity: .35}, {opacity: 1}], {duration: 260, easing: 'ease-out'});
    this.animations.add(animation);
    animation.onfinish = () => this.animations.delete(animation);
  },
  destroyed() {
    this.animations.forEach(animation => animation.cancel());
    this.el.removeEventListener('click', this.select);
    this.el.removeEventListener('keydown', this.keyboard);
  }
};

export default ManualCodex;
