export default {
  mounted() {
    this.page = 0;
    this.onPage = event => {
      const button = event.target.closest('[data-community-direction]');
      if (!button || button.getAttribute('aria-disabled') === 'true') return;
      this.page += Number(button.dataset.communityDirection);
      this.renderPage();
    };
    this.el.addEventListener('click', this.onPage);
    this.observer = new ResizeObserver(() => this.renderPage());
    this.groups = Array.from(this.el.querySelectorAll('[data-community-page-group]'));
    this.groups.forEach(group => this.observer.observe(group));
    this.renderPage();
  },

  updated() {
    this.renderPage();
  },

  destroyed() {
    this.el.removeEventListener('click', this.onPage);
    this.observer.disconnect();
  },

  renderPage() {
    const groups = this.groups.filter(group => group.clientHeight > 0);
    if (!groups.length) return;

    const size = Math.min(...groups.map(group => {
      const style = getComputedStyle(group);
      const columns = Number(style.getPropertyValue('--community-columns'));
      const tileHeight = parseFloat(style.getPropertyValue('--community-tile-height'));
      const gap = parseFloat(style.rowGap);
      return columns * Math.max(1, Math.floor((group.clientHeight + gap) / (tileHeight + gap)));
    }));
    const entries = groups.map(group => Array.from(group.querySelectorAll(':scope > [data-community-entry]')));
    const pages = Math.max(1, ...entries.map(list => Math.ceil(list.length / size)));
    this.page = Math.min(Math.max(this.page, 0), pages - 1);

    const start = this.page * size;
    entries.forEach(list => list.forEach((entry, index) => {
      entry.hidden = index < start || index >= start + size;
    }));

    const controls = this.el.querySelector('.community-pager-controls');
    controls.hidden = pages === 1;
    controls.querySelector('[data-community-page-label]').textContent = `${this.page + 1} / ${pages}`;
    controls.querySelector('[data-community-direction="-1"]').setAttribute('aria-disabled', String(this.page === 0));
    controls.querySelector('[data-community-direction="1"]').setAttribute('aria-disabled', String(this.page === pages - 1));
  }
};
