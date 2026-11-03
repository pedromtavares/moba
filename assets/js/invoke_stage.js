import InvokeCreation from './invoke_creation';

export const InvokeStage = {
  mounted() {
    this.mode = this.el.dataset.mode;
    this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.measure = () => {
      this.creation?.measureFooter?.();
      this.el.style.setProperty('--invoke-height', `${Math.max(0, window.innerHeight - (this.el.getBoundingClientRect().top + window.scrollY))}px`);
    };
    this.move = event => {
      if (this.reducedMotion || event.pointerType !== 'mouse') return;
      const rect = this.el.getBoundingClientRect();
      this.el.style.setProperty('--invoke-x', `${(event.clientX - rect.left - rect.width / 2) / rect.width * 10}px`);
      this.el.style.setProperty('--invoke-y', `${(event.clientY - rect.top - rect.height / 2) / rect.height * 6}px`);
    };
    this.leave = () => {
      this.el.style.setProperty('--invoke-x', '0px');
      this.el.style.setProperty('--invoke-y', '0px');
    };
    this.launch = event => {
      const button = event.target.closest('#create-button');
      if (button && !button.disabled) this.el.classList.add('is-invoking');
    };
    this.el.addEventListener('pointermove', this.move);
    this.el.addEventListener('pointerleave', this.leave);
    this.el.addEventListener('click', this.launch);
    window.addEventListener('resize', this.measure);
    this.measure();
    const artElement = this.el.querySelector('#invoke-art-stage');
    this.art = {...InvokeArt, el: artElement};
    this.art.mounted();
    this.creation = new InvokeCreation(this, url => {
      artElement.dataset.artUrl = url;
      this.art.updated();
    });
  },
  updated() {
    if (this.mode !== this.el.dataset.mode) {
      this.mode = this.el.dataset.mode;
      this.el.scrollIntoView({block: 'start'});
    }
    this.measure();
    this.el.classList.remove('is-invoking');
  },
  destroyed() {
    this.creation?.destroyed();
    this.art?.destroyed();
    this.el.removeEventListener('pointermove', this.move);
    this.el.removeEventListener('pointerleave', this.leave);
    this.el.removeEventListener('click', this.launch);
    window.removeEventListener('resize', this.measure);
  }
};

// Only the two artwork layers are managed here. LiveView still owns the roster,
// selection and forms; a late image load must never replace a newer selection.
export const InvokeArt = {
  mounted() {
    this.layers = [...this.el.querySelectorAll('.invoke-art-layer')];
    this.url = this.el.dataset.artUrl;
    this.active = 0;
    this.generation = 0;
  },
  updated() {
    const url = this.el.dataset.artUrl;
    if (url === this.url) return;
    this.url = url;
    const generation = ++this.generation;
    if (this.pending) this.pending.onload = this.pending.onerror = null;
    const image = new Image();
    this.pending = image;
    image.onload = () => {
      if (generation !== this.generation) return;
      const next = 1 - this.active;
      this.layers[next].src = url;
      this.layers[next].classList.add('is-active');
      this.layers[this.active].classList.remove('is-active');
      this.active = next;
      this.pending = null;
    };
    image.onerror = () => { if (generation === this.generation) this.pending = null; };
    image.src = url;
  },
  destroyed() {
    this.generation++;
    if (this.pending) this.pending.onload = this.pending.onerror = null;
  }
};
