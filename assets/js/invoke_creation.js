import {initialSelection, selectBuild, nameError} from './invoke_selection';

export default class InvokeCreation {
  constructor(hook, setArt) {
    this.hook = hook;
    this.el = hook.el;
    this.setArt = setArt;
    this.data = JSON.parse(this.el.dataset.creation);
    let saved;
    try { saved = JSON.parse(sessionStorage.getItem(this.data.storage_key)); } catch (_) { /* Storage is optional. */ }
    this.state = initialSelection(this.data, saved || this.data.initial);
    this.skills = new Map(this.data.skills.map(skill => [skill.id, skill]));
    this.click = event => {
      const control = event.target.closest('[data-invoke-action]');
      if (!control || !this.el.contains(control) || control.disabled) return;
      event.preventDefault();
      const type = control.dataset.invokeAction;
      if (type === 'create') return this.create();
      if (type === 'random') {
        const available = this.data.avatars.filter(avatar => !this.state.filter || avatar.role === this.state.filter);
        if (available.length) this.change({type: 'avatar', id: available[Math.floor(Math.random() * available.length)].id});
      } else this.change({type, id: control.dataset.skillId || control.dataset.avatarId, index: Number(control.dataset.buildIndex), role: control.dataset.role});
    };
    this.input = event => {
      if (event.target.matches('#invoke-name-form input')) {
        this.state = selectBuild(this.state, {type: 'name', name: event.target.value}, this.data);
        this.error = '';
        this.save();
        this.renderLaunch();
      }
    };
    this.submit = event => {
      if (event.target.id === 'invoke-name-form') { event.preventDefault(); this.create(); }
    };
    this.el.addEventListener('click', this.click);
    this.el.addEventListener('input', this.input);
    this.el.addEventListener('submit', this.submit);
    this.render(true);
    this.animate(this.el.querySelector('.invoke-build-panel'), [{opacity: 0, transform: 'translateY(12px)'}, {opacity: 1, transform: 'none'}], {duration: 420});
  }

  save() {
    try { sessionStorage.setItem(this.data.storage_key, JSON.stringify(this.state)); } catch (_) { /* Storage is optional. */ }
  }

  change(action) {
    const previous = this.state;
    this.state = selectBuild(previous, action, this.data);
    this.error = '';
    this.hook.hideTooltips?.();
    const panel = this.el.querySelector('.invoke-build-panel');
    panel.getAnimations().forEach(animation => animation.cancel());
    const before = panel.getBoundingClientRect();
    this.render(previous.avatar !== this.state.avatar);
    this.save();
    if (previous.custom !== this.state.custom) {
      this.el.scrollIntoView({block: 'start'});
      this.hook.measure();
      const after = panel.getBoundingClientRect();
      this.animate(panel, [
        {transform: `translate(${before.left - after.left}px, ${before.top - after.top}px) scale(${before.width / after.width}, ${before.height / after.height})`, opacity: .65},
        {transform: 'none', opacity: 1}
      ], {duration: 480});
      this.el.querySelectorAll('.invoke-custom-grid:not([hidden]) .invoke-skill-choice').forEach((tile, index) => {
        this.animate(tile, [{opacity: 0, transform: 'translateY(10px)'}, {opacity: 1, transform: 'none'}], {duration: 260, delay: Math.min(index * 12, 180)});
      });
    } else if (action.type === 'skill' || action.type === 'build') {
      this.animate(this.el.querySelector('#create-bar'), [{opacity: .55, transform: 'translateY(5px)'}, {opacity: 1, transform: 'none'}], {duration: 220});
    }
  }

  animate(element, frames, options) {
    if (this.hook.reducedMotion || !element.animate) return;
    element.getAnimations().forEach(animation => animation.cancel());
    element.animate(frames, {easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards', ...options});
  }

  render(heroChanged = false) {
    const avatar = this.data.avatars.find(avatar => avatar.id === this.state.avatar);
    this.el.dataset.mode = this.state.custom ? 'custom' : 'presets';
    this.el.dataset.role = avatar.role;
    this.el.setAttribute('aria-label', `Choose your hero · ${avatar.name}`);
    for (const [selector, hidden] of [['#invoke-custom-skills', !this.state.custom], ['#invoke-builds', this.state.custom], ['#custom-build-button', this.state.custom], ['#back-to-builds-button', !this.state.custom], ['#invoke-roster', this.state.custom]]) this.el.querySelector(selector).hidden = hidden;
    this.el.querySelector('.invoke-section-heading h2').textContent = this.state.custom ? 'Choose 3 skills' : 'Choose your build';
    if (heroChanged) {
      const identity = this.el.querySelector('[data-invoke-identity]');
      identity.id = `avatar-${avatar.id}`;
      identity.querySelector('#invoke-hero-name').textContent = avatar.name;
      identity.querySelector('[data-invoke-role]').textContent = avatar.role[0].toUpperCase() + avatar.role.slice(1);
      identity.querySelector('.invoke-role img').src = `/images/${avatar.role}_icon.png`;
      identity.querySelector('[data-invoke-description]').textContent = avatar.description;
      const ultimate = identity.querySelector('.invoke-signature');
      ultimate.setAttribute('title', avatar.ultimate.tooltip);
      ultimate.querySelector('img').src = avatar.ultimate.image;
      ultimate.querySelector('strong').textContent = avatar.ultimate.name;
      identity.querySelector('.invoke-details').id = `invoke-details-${avatar.id}`;
      Object.entries(avatar.stats).forEach(([stat, value]) => { identity.querySelector(`.invoke-base-stats [data-stat="${stat}"] dd`).textContent = value; });
      Object.entries(avatar.gains).forEach(([stat, value]) => { identity.querySelector(`.invoke-base-stats [data-stat="${stat}"] small`).textContent = `+${value} / level`; });
      Object.entries(avatar.ratings).forEach(([stat, value]) => {
        const meter = identity.querySelector(`.invoke-attributes [data-stat="${stat}"] [role=meter]`);
        meter.setAttribute('aria-valuenow', value);
        meter.querySelector('span').style.width = `${value}%`;
      });
      this.setArt(avatar.art);
      this.renderBuilds(avatar);
      this.animate(identity, [{opacity: .35, transform: 'translateX(-8px)'}, {opacity: 1, transform: 'none'}], {duration: 340});
    }
    this.el.querySelectorAll('.invoke-portrait').forEach(button => {
      button.hidden = !!this.state.filter && button.dataset.role !== this.state.filter;
      button.setAttribute('aria-pressed', String(button.dataset.avatarId === avatar.id));
    });
    const visible = this.data.avatars.filter(avatar => !this.state.filter || avatar.role === this.state.filter).length;
    this.el.querySelector('#invoke-avatars').style.setProperty('--invoke-columns', Math.min(12, Math.max(1, visible)));
    this.el.querySelectorAll('.invoke-filters [data-invoke-action=filter]').forEach(button => button.setAttribute('aria-pressed', String((button.dataset.role || null) === this.state.filter)));
    this.el.querySelectorAll('.invoke-build').forEach((build, index) => {
      const selected = index === this.state.preset;
      build.dataset.selected = String(selected);
      build.querySelector('button').setAttribute('aria-pressed', String(selected));
    });
    this.el.querySelectorAll('.invoke-skill-choice').forEach(button => {
      const selected = this.state.skills.includes(button.dataset.skillId);
      button.setAttribute('aria-pressed', String(selected));
      button.setAttribute('aria-disabled', String(!selected && this.state.skills.length === 3));
      button.querySelector('.invoke-check').hidden = !selected;
    });
    this.renderLoadout(avatar);
    this.renderLaunch();
    this.measureFooter();
    this.hook.refreshTooltips?.();
  }

  measureFooter() {
    this.el.style.setProperty('--invoke-footer-height', `${this.el.querySelector('#invoke-build-footer').getBoundingClientRect().height}px`);
  }

  renderBuilds(avatar) {
    const list = this.el.querySelector('#invoke-builds');
    list.replaceChildren(...this.data.builds[avatar.role].map((build, index) => {
      const node = this.el.querySelector('#invoke-build-option-template').content.firstElementChild.cloneNode(true);
      node.id = `invoke-build-${index}`;
      node.style.setProperty('--invoke-build-art', `url("${build.art}")`);
      const button = node.querySelector('button');
      button.id = `pick-build-${index}`;
      button.dataset.buildIndex = index;
      button.querySelector('.invoke-build-number').textContent = `0${index + 1}`;
      button.querySelector('strong').textContent = build.name;
      build.skills.forEach(id => {
        const skill = this.skills.get(id);
        if (!skill) return;
        const image = document.createElement('img');
        image.src = skill.image;
        image.alt = skill.name;
        image.tabIndex = 0;
        image.dataset.toggle = 'tooltip';
        image.title = skill.tooltip;
        image.id = `skill_build_${id}_${index}`;
        node.querySelector('.invoke-build-skills').append(image);
      });
      return node;
    }));
  }

  renderLoadout(avatar) {
    const list = this.el.querySelector('.invoke-loadout-skills');
    const nodes = this.state.skills.map(id => this.skillSlot(this.skills.get(id)));
    while (nodes.length < 3) nodes.push(this.el.querySelector('#invoke-empty-skill-template').content.firstElementChild.cloneNode(true));
    nodes.push(this.skillSlot(avatar.ultimate, true));
    list.replaceChildren(...nodes);
    this.el.querySelector('#create-bar h3').textContent = this.state.preset === null ? (this.state.skills.length ? 'Custom Build' : 'Skill Build') : this.data.builds[avatar.role][this.state.preset].name;
    this.el.querySelector('#create-bar header > strong').firstChild.textContent = this.state.skills.length;
  }

  skillSlot(skill, ultimate = false) {
    const slot = this.el.querySelector('#invoke-selected-skill-template').content.firstElementChild.cloneNode(true);
    const button = slot.querySelector('button');
    const image = button.querySelector('img');
    image.src = skill.image;
    image.alt = skill.name;
    image.title = skill.tooltip;
    if (ultimate || !this.state.custom) {
      image.id = `skill_${skill.id}`;
      image.tabIndex = 0;
      button.replaceWith(image);
    } else {
      button.id = `skill_${skill.id}`;
      button.dataset.skillId = skill.id;
      button.setAttribute('aria-label', `Remove ${skill.name}`);
    }
    slot.querySelector('strong').textContent = skill.name;
    slot.querySelector('[data-energy]').textContent = skill.energy;
    slot.querySelector('.invoke-energy').setAttribute('aria-label', `Energy cost: ${skill.energy}`);
    if (ultimate) {
      slot.classList.add('invoke-ultimate-slot');
      slot.querySelector('small').hidden = false;
    }
    return slot;
  }

  renderLaunch() {
    const avatar = this.data.avatars.find(avatar => avatar.id === this.state.avatar);
    const button = this.el.querySelector('#create-button');
    const error = this.error || nameError(this.state.name, this.data.named);
    button.disabled = !!this.creating || !!error || this.state.skills.length !== 3;
    button.dataset.heroName = avatar.name;
    button.dataset.heroArt = avatar.art;
    const input = this.el.querySelector('#invoke-name-form input');
    if (input && input.value !== this.state.name) input.value = this.state.name;
    const errorNode = this.el.querySelector('#invoke-name-error') || this.el.querySelector('#invoke-create-error');
    errorNode.textContent = error;
    errorNode.hidden = !error;
    const form = this.el.querySelector('#invoke-guest-form');
    if (form) {
      form.querySelector('[name=avatar]').value = avatar.id;
      form.querySelectorAll('[name="skills[]"]').forEach(input => input.remove());
      this.state.skills.forEach(id => {
        const input = document.createElement('input');
        input.type = 'hidden'; input.name = 'skills[]'; input.value = id; form.append(input);
      });
    }
  }

  create() {
    if (this.el.querySelector('#create-button').disabled) return;
    this.creating = true;
    this.renderLaunch();
    this.el.classList.add('is-invoking');
    this.hook.pushEvent('create', {avatar: this.state.avatar, skills: this.state.skills, name: this.state.name}, reply => {
      if (reply.ok) {
        try { sessionStorage.removeItem(this.data.storage_key); } catch (_) { /* Storage is optional. */ }
      } else {
        this.creating = false;
        this.error = reply.error || 'Unable to create your hero. Please try again.';
        this.el.classList.remove('is-invoking');
        this.renderLaunch();
      }
    });
  }

  destroyed() {
    this.el.removeEventListener('click', this.click);
    this.el.removeEventListener('input', this.input);
    this.el.removeEventListener('submit', this.submit);
    this.el.querySelectorAll('*').forEach(element => element.getAnimations?.().forEach(animation => animation.cancel()));
  }
}
