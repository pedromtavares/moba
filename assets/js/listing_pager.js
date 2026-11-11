export function pageStarts(heights, gap, availableHeight) {
  const starts = [0];
  let usedHeight = 0;

  heights.forEach((height, index) => {
    const nextHeight = usedHeight + gap + height;
    if (index === starts.at(-1)) {
      usedHeight = height;
    } else if (nextHeight > availableHeight + 0.5) {
      starts.push(index);
      usedHeight = height;
    } else {
      usedHeight = nextHeight;
    }
  });

  return starts;
}

export default {
  mounted() {
    this.viewport = this.el.querySelector('.listing-pager-viewport');
    this.controls = this.el.querySelector('.listing-pager-controls');
    this.page = 0;
    this.onPage = event => {
      const button = event.target.closest('[data-page-step]');
      if (!button || button.getAttribute('aria-disabled') === 'true') return;

      this.hideTooltips();
      this.page += Number(button.dataset.pageStep);
      this.anchor = this.starts[this.page];
      this.renderPage();
    };

    this.controls.addEventListener('click', this.onPage);
    if (!this.el.dataset.pageSize) {
      this.observer = new ResizeObserver(() => this.measure());
      this.observer.observe(this.viewport);
      document.fonts?.ready.then(() => {
        if (this.el.isConnected) this.measure();
      });
    }
    this.measure();
  },

  updated() {
    this.measure();
  },

  destroyed() {
    this.controls.removeEventListener('click', this.onPage);
    this.observer?.disconnect();
  },

  measure() {
    const list = this.viewport.querySelector('[data-listing-rows]');
    this.rows = Array.from(list?.children || []);
    const pageSize = Number(this.el.dataset.pageSize);
    this.starts = pageSize > 0 ? fixedPageStarts(this.rows.length, pageSize) : this.fitPages(list);
    this.controls.hidden = this.starts.length === 1;

    const index = this.anchor ?? this.rows.findIndex(row => row.id === this.el.dataset.initialRow);
    this.page = Math.max(0, this.starts.findLastIndex(start => start <= index));
    this.renderPage();
  },

  fitPages(list) {
    this.rows.forEach(row => { row.hidden = false; });
    this.controls.hidden = true;

    const heights = this.rows.map(row => row.getBoundingClientRect().height);
    const gap = list ? parseFloat(getComputedStyle(list).rowGap) || 0 : 0;
    const table = list?.closest('table');
    const tableChrome = table ? table.getBoundingClientRect().height - list.getBoundingClientRect().height : 0;
    const availableHeight = () => this.viewport.getBoundingClientRect().height - tableChrome;

    const pages = pageStarts(heights, gap, availableHeight());
    if (pages.length === 1) return pages;

    this.controls.hidden = false;
    return pageStarts(heights, gap, availableHeight());
  },

  renderPage() {
    const start = this.starts[this.page];
    const end = this.starts[this.page + 1] ?? this.rows.length;
    this.rows.forEach((row, index) => { row.hidden = index < start || index >= end; });

    const label = this.controls.querySelector('[data-page-label]');
    const text = `${this.page + 1} / ${this.starts.length}`;
    if (label.textContent !== text) label.textContent = text;
    this.controls.querySelector('[data-page-step="-1"]').setAttribute('aria-disabled', String(this.page === 0));
    this.controls.querySelector('[data-page-step="1"]').setAttribute('aria-disabled', String(this.page === this.starts.length - 1));
  }
};
export function fixedPageStarts(rowCount, pageSize) {
  return Array.from({length: Math.max(1, Math.ceil(rowCount / pageSize))}, (_, page) => page * pageSize);
}

