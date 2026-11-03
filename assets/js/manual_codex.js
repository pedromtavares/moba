const ManualCodex = {
  mounted() {
    this.choices = [...this.el.querySelectorAll('[data-manual-pick]')];
    this.details = [...this.el.querySelectorAll('[data-manual-detail]')];
    this.animations = new Set();
    this.selectedRank = 1;
    this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.select = event => {
      const control = event.target.closest('[data-manual-pick], [data-manual-rank]');
      if (!control || !this.el.contains(control)) return;
      if (control.dataset.manualPick) this.pick(control.dataset.code, true);
      else this.rank(control);
      event.preventDefault();
    };
    this.keyboard = event => {
      if (!event.target.dataset.manualRank || event.altKey || event.ctrlKey || event.metaKey ||
          !['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      const controls = [...event.target.closest('[data-manual-ranked]').querySelectorAll('[data-manual-rank]')];
      const index = controls.indexOf(event.target);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? controls.length - 1 :
        (index + (['ArrowUp', 'ArrowLeft'].includes(event.key) ? -1 : 1) + controls.length) % controls.length;
      event.preventDefault();
      event.stopPropagation();
      this.rank(controls[next]);
      controls[next].focus({preventScroll: true});
    };
    this.el.addEventListener('click', this.select);
    this.el.addEventListener('keydown', this.keyboard);
  },
  pick(code, scroll = false) {
    const detail = this.details.find(panel => panel.dataset.code === code);
    if (!detail) return;
    this.hideTooltips?.();
    this.details.forEach(panel => { panel.hidden = panel !== detail; });
    this.choices.forEach(choice => choice.setAttribute('aria-pressed', String(choice.dataset.code === code)));
    const ranks = [...detail.querySelectorAll('[data-manual-rank]')];
    const rank = ranks.find(button => Number(button.dataset.manualRank) === this.selectedRank) || ranks.at(-1);
    if (rank) this.rank(rank, false);
    this.reveal(detail);
    if (scroll && window.innerWidth < 768) detail.scrollIntoView({block: 'start', behavior: this.reducedMotion ? 'auto' : 'smooth'});
  },
  rank(button, remember = true) {
    if (remember) this.selectedRank = Number(button.dataset.manualRank);
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
    const animation = element.animate([{opacity: .3, transform: 'translateY(8px)'}, {opacity: 1, transform: 'none'}], {duration: 320, easing: 'cubic-bezier(.2,.7,.2,1)'});
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
