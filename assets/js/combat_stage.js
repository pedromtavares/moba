const number = value => Math.round(Number(value) || 0);
const percent = (value, total) => total > 0 ? Math.max(0, Math.min(100, value / total * 100)) : 0;

export default {
  mounted() {
    this.epoch = 0;
    this.animations = new Set();
    this.waits = new Map();
    this.queue = [];
    this.busy = false;
    this.actions = {};
    this.activeEffects = {};
    this.motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    this.sound = false;
    try { this.sound = localStorage.getItem('moba-combat-sound') === 'on'; } catch (_) { /* optional preference */ }
    this.soundButton = this.el.querySelector('[data-stage-sound]');
    this.replayButton = this.el.querySelector('[data-stage-replay]');
    this.onSound = () => {
      this.sound = !this.sound;
      this.unlockSound();
      try { localStorage.setItem('moba-combat-sound', this.sound ? 'on' : 'off'); } catch (_) { /* optional preference */ }
      this.soundLabel();
    };
    this.onReplay = () => {
      if (this.busy || !this.scene.events.length) return;
      this.queue.push(...this.scene.events.slice(-2));
      this.drain();
    };
    this.guard = event => {
      this.unlockSound();
      if (this.busy && event.target.closest('#attack-button, [data-battle-continue=true]')) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    };
    this.soundButton.addEventListener('click', this.onSound);
    this.replayButton.addEventListener('click', this.onReplay);
    document.addEventListener('click', this.guard, true);
    this.soundLabel();
    this.reset(JSON.parse(this.el.dataset.scene));
  },

  updated() {
    const scene = JSON.parse(this.el.dataset.scene);
    if (scene.id !== this.scene.id) return this.reset(scene);
    this.scene = scene;
    this.renderLogToggle();
    const fresh = scene.events.filter(event => event.number > this.seen);
    this.seen = Math.max(this.seen, ...scene.events.map(event => event.number));
    this.queue.push(...fresh);
    if (!this.busy && this.queue.length) this.drain();
    else if (!this.busy) this.settle();
  },

  disconnected() { this.cancel(); this.settle(); },
  destroyed() {
    this.cancel();
    this.soundButton.removeEventListener('click', this.onSound);
    this.replayButton.removeEventListener('click', this.onReplay);
    document.removeEventListener('click', this.guard, true);
    if (this.audio) this.audio.close().catch(() => {});
  },

  reset(scene) {
    this.cancel();
    this.scene = scene;
    this.actions = {};
    this.activeEffects = {};
    this.seen = Math.max(0, ...scene.events.map(event => event.number));
    scene.units.forEach(unit => this.renderBuild(unit));
    this.settle();
  },

  renderBuild(unit) {
    const build = this.el.querySelector(`[data-build-side="${unit.side}"]`);
    build.setAttribute('aria-label', `${unit.name} loadout`);
    const fighter = this.el.querySelector(`[data-side="${unit.side}"]`);
    fighter.querySelector('[data-build-league]').src = `/images/league/${unit.build.tier}.png`;
    fighter.querySelector('[data-build-difficulty]').textContent = unit.build.difficulty;
    ['skills', 'items'].forEach(kind => {
      const row = build.querySelector(`[data-build-${kind}]`);
      row.setAttribute('aria-label', `${unit.name} ${kind}`);
      row.hidden = !unit.build[kind].length;
      row.replaceChildren(...unit.build[kind].map(resource => {
        const tile = document.createElement('span');
        tile.className = 'stage-build-resource';
        tile.dataset.buildCode = resource.code;
        const image = document.createElement('img');
        image.id = `stage-build-${unit.side}-${kind === 'skills' ? 'skill' : 'item'}-${resource.id}`;
        image.src = resource.image;
        image.alt = resource.name;
        image.title = resource.tooltip;
        image.setAttribute('data-toggle', 'tooltip');
        image.tabIndex = 0;
        const cooldown = document.createElement('span');
        cooldown.setAttribute('data-build-cooldown', '');
        cooldown.setAttribute('aria-label', `${resource.name} cooldown in turns`);
        cooldown.hidden = true;
        tile.append(image, cooldown);
        return tile;
      }));
    });
    this.refreshTooltips();
  },

  cancel() {
    if (this.logScrollFrame) cancelAnimationFrame(this.logScrollFrame);
    this.epoch++;
    this.queue = [];
    this.busy = false;
    this.animations.forEach(animation => animation.cancel());
    this.animations.clear();
    this.waits.forEach((resolve, timer) => { clearTimeout(timer); resolve(); });
    this.waits.clear();
    if (this.el) {
      this.el.dataset.presenting = 'false';
      this.el.querySelector('.stage-vfx').replaceChildren();
    }
  },

  soundLabel() {
    this.soundButton.textContent = this.sound ? 'Sound on' : 'Sound off';
    this.soundButton.setAttribute('aria-pressed', String(this.sound));
  },

  unlockSound() {
    if (!this.sound) return;
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) return;
    this.audio = this.audio || new Audio();
    if (this.audio.state === 'suspended') this.audio.resume().catch(() => {});
  },

  setUnits(units) {
    units.forEach(unit => {
      const fighter = this.el.querySelector(`[data-side="${unit.side}"]`);
      if (unit.art) {
        fighter.querySelector('.stage-art').src = unit.art;
        fighter.querySelector('.stage-art').alt = unit.avatar;
      }
      if (unit.name) fighter.querySelector('[data-unit-name]').textContent = unit.name;
      fighter.querySelector('[data-unit-allegiance]').textContent = unit.you ? 'Your hero' : unit.avatar;
      fighter.querySelector('[data-unit-level]').textContent = `Level ${unit.level}${unit.you ? ` · ${unit.avatar}` : ''}`;
      fighter.querySelector('.stage-health').setAttribute('aria-label', `${unit.name} health`);
      const action = this.el.querySelector(`[data-action-side="${unit.side}"]`);
      action.setAttribute('aria-label', `${unit.name} last action`);
      action.querySelector('[data-stage-action-owner]').textContent = unit.you ? 'Your last action' : `${unit.name}’s last action`;
      action.querySelector('[data-stage-effects]').setAttribute('aria-label', `${unit.name} triggered effects`);
      this.setVitals(unit.side, unit);
    });
  },

  setVitals(side, unit) {
    const fighter = this.el.querySelector(`[data-side="${side}"]`);
    fighter.dataset.dead = String(unit.hp <= 0);
    this.renderControlStatuses(fighter, unit);
    fighter.querySelector('[data-unit-hp]').textContent = number(unit.hp);
    fighter.querySelector('[data-unit-max-hp]').textContent = number(unit.maxHp);
    fighter.querySelector('[data-unit-mp]').textContent = `${number(unit.mp)} / ${number(unit.maxMp)}`;
    const hp = `${percent(unit.hp, unit.maxHp)}%`;
    fighter.querySelector('.stage-health-fill').style.width = hp;
    fighter.querySelector('.stage-health-trail').style.width = hp;
    fighter.querySelector('.stage-energy-fill').style.width = `${percent(unit.mp, unit.maxMp)}%`;
    const gauge = fighter.querySelector('.stage-health');
    gauge.setAttribute('aria-valuenow', number(unit.hp));
    gauge.setAttribute('aria-valuemax', number(unit.maxHp));
    this.renderCombatStats(fighter, unit.combatStats);
    this.activeEffects[side] = unit.activeEffects;
    this.renderEffectIcons(side);
    this.renderBuildCooldowns(side, unit.cooldowns);
  },

  renderCombatStats(fighter, stats) {
    stats.forEach(stat => {
      const badge = fighter.querySelector(`[data-combat-stat="${stat.key}"]`);
      const previous = Number(badge.dataset.statTotal);
      const previousDelta = Number(badge.dataset.statDelta);
      const value = number(stat.value);
      const delta = number(stat.modifier);
      badge.title = stat.tooltip;
      badge.dataset.statTotal = String(value);
      badge.dataset.statDelta = String(delta);
      badge.dataset.statState = delta > 0 ? 'buff' : delta < 0 ? 'debuff' : 'normal';
      badge.querySelector('[data-stat-value]').textContent = value;
      const modifier = badge.querySelector('[data-stat-modifier]');
      modifier.hidden = delta === 0;
      modifier.dataset.tone = delta < 0 ? 'negative' : 'positive';
      modifier.textContent = `${delta > 0 ? '+' : ''}${delta}`;

      const changed = Number.isFinite(previous) && (previous !== value || previousDelta !== delta);
      if (changed && ['attack', 'power', 'armor'].includes(stat.key) && !this.motion.matches && !document.hidden) {
        const increase = value !== previous ? value > previous : delta > previousDelta;
        const glow = increase ? '#8ce4ba' : '#ff9caa';
        this.animate(badge, [
          {transform: 'scale(1)', boxShadow: `0 0 0 0 ${glow}00`},
          {offset: .25, transform: 'scale(1.06)', boxShadow: `0 0 0 2px ${glow}bb, 0 0 28px ${glow}88`, borderColor: glow},
          {offset: .65, transform: 'scale(1.025)', boxShadow: `0 0 0 1px ${glow}66, 0 0 18px ${glow}55`, borderColor: glow},
          {transform: 'scale(1)'}
        ], 650);
      }
    });
  },

  renderBuildCooldowns(side, cooldowns = {}) {
    this.el.querySelectorAll(`[data-build-side="${side}"] [data-build-code]`).forEach(tile => {
      const remaining = Math.max(0, number(cooldowns[tile.dataset.buildCode]));
      tile.dataset.cooling = String(remaining > 0);
      const badge = tile.querySelector('[data-build-cooldown]');
      badge.hidden = remaining === 0;
      badge.textContent = remaining;
    });
  },

  renderControlStatuses(fighter, unit) {
    ['stunned', 'silenced', 'disarmed'].forEach(status => {
      const active = unit.hp > 0 && unit.statuses?.[status] === true;
      fighter.dataset[status] = String(active);
      fighter.querySelector(`[data-control-label="${status}"]`).hidden = !active;
    });
  },

  settle() {
    this.renderLogToggle();
    this.el.dataset.finished = String(this.scene.finished);
    this.el.dataset.presenting = 'false';
    this.el.dataset.next = this.scene.finished ? '' : this.scene.next;
    this.setUnits(this.scene.units);
    this.el.querySelector('[data-stage-status]').textContent = this.scene.status;
    this.el.querySelector('[data-stage-context]').textContent = this.scene.context;
    this.el.querySelector('[data-stage-initiated]').textContent = `Started by ${this.scene.initiator}`;
    const opening = this.el.querySelector('#battle-ready');
    opening.hidden = this.scene.events.length > 0;
    const yourTurn = this.scene.status === 'Your turn';
    opening.dataset.state = yourTurn ? 'ready' : 'waiting';
    opening.querySelector('[data-stage-ready-title]').textContent = yourTurn ? 'Make your first move' : this.scene.status;
    opening.querySelector('[data-stage-ready-copy]').textContent = yourTurn ? 'Select a skill below, then attack.' : this.scene.units.some(unit => unit.you) ? 'Your opponent moves first.' : 'The battle will appear here when it starts.';
    const last = this.scene.events[this.scene.events.length - 1];
    this.renderActions(this.scene.events);
    this.el.querySelector('[data-stage-turn]').textContent = this.scene.events.length + (this.scene.finished ? 0 : 1);
    this.replayButton.hidden = !last;
    const result = this.el.querySelector('[data-stage-result]');
    result.hidden = !this.scene.finished;
    result.dataset.winner = this.scene.winner || 'draw';
    result.querySelector('[data-stage-result-title]').textContent = this.scene.status;
  },

  headline(event) {
    this.renderAction(event.actor, event);
    this.el.querySelector('[data-stage-turn]').textContent = event.number;
  },

  renderLogToggle() {
    const expanded = this.el.dataset.logExpanded === 'true';
    const toggles = [...this.el.querySelectorAll('[data-stage-log-toggle]')];
    const opening = expanded && toggles.some(toggle => toggle.getAttribute('aria-expanded') !== 'true');
    const label = expanded ? 'Hide battle log' : 'Battle log';
    toggles.forEach(toggle => {
      toggle.disabled = this.scene.events.length === 0;
      toggle.setAttribute('aria-expanded', String(expanded));
      toggle.setAttribute('aria-label', `${label} (${this.scene.events.length} turns)`);
      toggle.querySelector('[data-stage-log-label]').textContent = label;
      toggle.querySelector('[data-stage-log-count]').textContent = this.scene.events.length;
    });
    if (opening) {
      if (this.logScrollFrame) cancelAnimationFrame(this.logScrollFrame);
      this.logScrollFrame = requestAnimationFrame(() => {
        document.getElementById('combat-log-panel')?.scrollIntoView({behavior: this.motion.matches ? 'auto' : 'smooth', block: 'start'});
      });
    }
  },

  renderActions(events) {
    ['left', 'right'].forEach(side => {
      const last = [...events].reverse().find(event => event.actor === side);
      this.renderAction(side, last);
    });
  },

  renderAction(side, event) {
    this.actions[side] = event;
    const action = this.el.querySelector(`[data-action-side="${side}"]`);
    const image = action.querySelector('[data-stage-skill]');
    action.querySelector('.stage-ability-ring').hidden = !event;
    image.src = event ? event.image : '/images/basic_attack.png';
    image.alt = event ? event.skill : '';
    if (event) {
      image.setAttribute('data-toggle', 'tooltip');
      image.title = event.tooltip;
    } else {
      image.removeAttribute('data-toggle');
      image.removeAttribute('title');
    }
    action.querySelector('[data-stage-skill-name]').textContent = event ? event.skill : 'No action yet';
    action.querySelector('[data-stage-flag]').textContent = event ? event.flag || '' : '';
    const damage = action.querySelector('[data-stage-summary]');
    const evaded = event?.flag === 'Evaded' && !event.damage;
    damage.textContent = evaded ? 'EVADED' : event ? event.damage > 0 ? `−${number(event.damage)}` : '0' : '';
    damage.dataset.outcome = evaded ? 'evaded' : '';
    if (evaded) action.querySelector('[data-stage-flag]').textContent = '';
    damage.dataset.damage = event ? number(event.damage) : 0;
    damage.setAttribute('aria-label', event ? event.summary : '');
    this.renderEffectIcons(side);
    this.refreshTooltips();
  },

  renderEffectIcons(side) {
    const action = this.el.querySelector(`[data-action-side="${side}"]`);
    const event = this.actions[side];
    const active = this.activeEffects[side] || [];
    const primary = event && active.find(effect => effect.code === event.code);
    const badge = action.querySelector('[data-skill-duration]');
    badge.hidden = !(primary && primary.duration);
    badge.textContent = primary ? primary.duration || '' : '';
    if (event) action.querySelector('[data-stage-skill]').title = event.tooltip + (primary ? primary.tooltip : '');
    const triggered = event ? event.effects : [];
    const effects = triggered.map(effect => {
      const ongoing = active.find(buff => buff.code === effect.code);
      return ongoing ? {...effect, duration: ongoing.duration, kind: ongoing.kind, tooltip: effect.tooltip + ongoing.tooltip} : effect;
    });
    effects.push(...active.filter(effect => (!event || effect.code !== event.code) && !triggered.some(trigger => trigger.code === effect.code)));
    action.querySelector('[data-stage-effects]').replaceChildren(...effects.map(effect => {
      const tile = document.createElement('span');
      tile.className = 'stage-effect-icon';
      tile.dataset.kind = effect.kind || 'triggered';
      tile.setAttribute('role', 'listitem');
      tile.title = effect.tooltip;
      tile.setAttribute('data-toggle', 'tooltip');
      tile.setAttribute('tabindex', '0');
      tile.setAttribute('aria-label', `${effect.name}: ${effect.description}`);
      const icon = document.createElement(effect.image ? 'img' : 'span');
      if (effect.image) {
        icon.src = effect.image;
        icon.alt = effect.name;
      } else {
        icon.className = 'stage-effect-name';
        icon.textContent = effect.name;
      }
      tile.append(icon);
      if (effect.duration) {
        const duration = document.createElement('small');
        duration.className = 'stage-effect-duration';
        duration.textContent = effect.duration;
        tile.append(duration);
      }
      return tile;
    }));
  },

  async drain() {
    if (this.busy) return;
    this.busy = true;
    const epoch = this.epoch;
    this.el.dataset.presenting = 'true';
    this.el.querySelector('[data-stage-result]').hidden = true;
    this.el.querySelector('[data-stage-status]').textContent = 'Resolving…';
    this.el.querySelector('#battle-ready').hidden = true;
    this.renderActions(this.scene.events.filter(event => event.number < this.queue[0].number));
    try {
      while (this.queue.length && epoch === this.epoch) await this.play(this.queue.shift(), epoch);
    } finally {
      if (epoch === this.epoch) {
        this.busy = false;
        this.settle();
      }
    }
  },

  async play(event, epoch) {
    this.headline(event);
    this.el.dataset.direction = event.actor;
    this.el.dataset.kind = event.kind;
    if (this.motion.matches || document.hidden) {
      Object.entries(event.after).forEach(([side, unit]) => this.setVitals(side, unit));
      return;
    }
    Object.entries(event.before).forEach(([side, unit]) => this.setVitals(side, unit));
    const actor = this.el.querySelector(`[data-side="${event.actor}"] .stage-art`);
    const target = this.el.querySelector(`[data-side="${event.target}"]`);
    const sign = event.actor === 'left' ? 1 : -1;
    this.animate(this.el.querySelector(`[data-action-side="${event.actor}"] .stage-ability-ring`), [{transform:'scale(.85)', boxShadow:'0 0 0 #eac78b00'}, {offset:.35, transform:'scale(1.12)', boxShadow:'0 0 45px #eac78b66'}, {transform:'scale(1)', boxShadow:'0 0 0 #eac78b00'}], 500);
    if (!['Stunned', 'Charging'].includes(event.flag)) {
      this.animate(actor, [{filter:'brightness(1)', transform:'scale(1.02)'}, {filter:'brightness(1.35)', transform:`scale(1.045) translateX(${sign * 6}px)`}, {filter:'brightness(1)', transform:'scale(1.02)'}], 440);
      const bolt = document.createElement('img');
      bolt.className = `stage-projectile ${event.kind}`;
      bolt.src = event.image;
      this.el.querySelector('.stage-vfx').append(bolt);
      this.animate(bolt, [{left:event.actor === 'left' ? '29%' : '71%', opacity:0, transform:'translate(-50%, -50%) scale(.3) rotate(-20deg)'}, {offset:.25, opacity:1}, {left:event.target === 'left' ? '24%' : '76%', opacity:1, transform:'translate(-50%, -50%) scale(1.2) rotate(15deg)'}], 280).then(() => bolt.remove());
      this.tone(event.kind === 'spell' ? 420 : 140, .09);
    }
    await this.wait(275);
    if (epoch !== this.epoch) return;
    if (!['Stunned','Charging','Evaded','Miss'].includes(event.flag)) {
      this.animate(target.querySelector('.stage-art'), [{filter:'brightness(1)'}, {filter:'brightness(1.9) sepia(.25)', transform:`scale(1.02) translateX(${-sign * 7}px)`}, {filter:'brightness(1)', transform:'scale(1.02)'}], 300);
      const flash = document.createElement('span');
      flash.className = `stage-impact ${event.target}`;
      this.el.querySelector('.stage-vfx').append(flash);
      this.animate(flash, [{opacity:0, transform:'scale(.3)'}, {offset:.2, opacity:.8}, {opacity:0, transform:'scale(2)'}], 380).then(() => flash.remove());
    } else if (event.flag === 'Evaded') {
      this.evade(event.target);
    }
    Object.entries(event.after).forEach(([side, unit]) => {
      const change = number(unit.hp - event.before[side].hp);
      if (change) this.float(side, `${change > 0 ? '+' : '−'}${Math.abs(change)}`, change > 0 ? 'heal' : 'damage');
      this.setVitals(side, unit);
      if (unit.hp <= 0 && event.before[side].hp > 0) {
        const fallen = this.el.querySelector(`[data-side="${side}"]`);
        this.animate(fallen, [{filter:'brightness(1.5) saturate(.5)'}, {filter:'grayscale(1) brightness(.6)'}], 650);
      }
    });
    this.refreshTooltips();
    if (event.flag && event.flag !== 'Evaded') this.float(['Stunned', 'Charging'].includes(event.flag) ? event.actor : event.target, event.flag.toUpperCase(), 'status');
    this.tone(event.flag === 'Critical' ? 65 : 90, .1);
    await this.wait(410);
  },

  evade(side) {
    const fighter = this.el.querySelector(`[data-side="${side}"]`);
    const art = fighter.querySelector('.stage-art');
    const field = fighter.querySelector('.stage-control-vfx');
    const direction = side === 'left' ? -1 : 1;
    const echo = document.createElement('img');
    echo.className = 'stage-evade-echo';
    echo.src = art.src;
    echo.alt = '';
    field.append(echo);
    this.animate(echo, [{opacity:0}, {offset:.2, opacity:.4}, {opacity:0, transform:`scale(1.02) translateX(${-direction * 22}px)`}], 650).then(() => echo.remove());
    this.animate(art, [{opacity:1, transform:'scale(1.02)'}, {offset:.28, opacity:.25, transform:`scale(1.035) translateX(${direction * 42}px)`}, {offset:.65, opacity:.65, transform:`scale(1.02) translateX(${direction * 14}px)`}, {opacity:1, transform:'scale(1.02)'}], 550);
    const wind = document.createElement('span');
    wind.className = 'stage-evade-wind';
    field.append(wind);
    this.animate(wind, [{opacity:0, transform:`translateX(${-direction * 25}px)`}, {offset:.25, opacity:.85}, {opacity:0, transform:`translateX(${direction * 55}px)`}], 550).then(() => wind.remove());
    this.float(side, 'EVADED', 'evade');
  },

  float(side, text, kind) {
    const label = document.createElement('strong');
    label.className = `stage-float ${side} ${kind}`;
    label.textContent = text;
    this.el.querySelector('.stage-vfx').append(label);
    this.animate(label, [{opacity:0, transform:'translate(-50%, 15px) scale(.7)'}, {offset:.2, opacity:1, transform:'translate(-50%, 0) scale(1.08)'}, {offset:.7, opacity:1}, {opacity:0, transform:'translate(-50%, -65px) scale(1)'}], kind === 'evade' ? 1150 : 900).then(() => label.remove());
  },

  animate(element, frames, duration) {
    const animation = element.animate(frames, {duration: duration * 2, easing:'cubic-bezier(.2,.7,.2,1)'});
    this.animations.add(animation);
    return animation.finished.catch(() => {}).finally(() => this.animations.delete(animation));
  },

  wait(duration) {
    return new Promise(resolve => {
      const timer = setTimeout(() => { this.waits.delete(timer); resolve(); }, duration * 2);
      this.waits.set(timer, resolve);
    });
  },

  tone(frequency, duration) {
    if (!this.sound || !this.audio || this.audio.state !== 'running') return;
    const oscillator = this.audio.createOscillator();
    const gain = this.audio.createGain();
    const now = this.audio.currentTime;
    oscillator.type = 'triangle';
    oscillator.frequency.setValueAtTime(frequency, now);
    oscillator.frequency.exponentialRampToValueAtTime(Math.max(frequency / 3, 30), now + duration);
    gain.gain.setValueAtTime(.045, now);
    gain.gain.exponentialRampToValueAtTime(.001, now + duration);
    oscillator.connect(gain);
    gain.connect(this.audio.destination);
    oscillator.start(now);
    oscillator.stop(now + duration);
  }
};
