import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const source = await readFile(new URL('./combat_stage.js', import.meta.url), 'utf8');
const {default: CombatStage} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('incoming turns join the current sequence once, including duplicate server updates', async () => {
  const played = [];
  let finishFirst;
  const firstFinished = new Promise(resolve => { finishFirst = resolve; });
  const nodes = {'[data-stage-result]': {}, '[data-stage-status]': {}, '#battle-ready': {}};
  const hook = Object.assign({}, CombatStage, {
    epoch: 1, busy: false, seen: 1, queue: [{number: 1}],
    scene: {id: 12, events: [{number: 1}]},
    el: {dataset: {}, querySelector: selector => nodes[selector]},
    settled: 0,
    renderActions() {},
    renderLogToggle() {},
    settle() { this.settled++; },
    async play(event) {
      played.push(event.number);
      if (event.number === 1) await firstFinished;
    }
  });
  const running = hook.drain();
  hook.el.dataset.scene = JSON.stringify({id: 12, events: [{number: 1}, {number: 2}, {number: 3}]});
  hook.updated();
  hook.updated();
  assert.deepEqual(played, [1]);
  assert.equal(hook.busy, true);
  finishFirst();
  await running;
  assert.deepEqual(played, [1, 2, 3]);
  assert.equal(hook.settled, 1);
  assert.equal(hook.busy, false);
});

test('each hero retains its own latest action and every effect icon across responses and resets', t => {
  const originalDocument = globalThis.document;
  globalThis.document = {createElement: () => ({dataset: {}, setAttribute() {}, append(child) { if (!this.image) this.image = child; else this.badge = child; }})};
  t.after(() => { globalThis.document = originalDocument; });
  const makeAction = () => {
    const nodes = {};
    ['.stage-ability-ring', '[data-stage-skill]', '[data-stage-skill-name]', '[data-stage-flag]', '[data-stage-summary]', '[data-skill-duration]'].forEach(selector => { nodes[selector] = {dataset: {}, setAttribute(name, value) { this[name] = value; }, removeAttribute(name) { delete this[name]; }}; });
    nodes['[data-stage-effects]'] = {replaceChildren(...icons) { this.icons = icons; }};
    return {nodes, querySelector: selector => nodes[selector]};
  };
  const left = makeAction();
  const right = makeAction();
  const counter = {};
  const hook = Object.assign({}, CombatStage, {
    actions: {}, activeEffects: {},
    el: {querySelector: selector => selector === '[data-stage-turn]' ? counter : selector.includes('left') ? left : right}, refreshTooltips() {}
  });
  const action = (actor, number, skill, count) => ({actor, number, skill, code: skill.toLowerCase().replaceAll(' ', '_'), image: `${skill}.png`, summary: `${actor} used ${skill}`, damage: number * 10, tooltip: `<h3>${skill}</h3>Actual action`, effects: Array.from({length: count}, (_, index) => ({code: `effect_${index}`, name: `Effect ${index}`, image: `${index}.png`, description: `Triggered ${index}`, tooltip: `<h3>Effect ${index}</h3>Triggered ${index}`}))});
  const player = action('left', 3, 'Empower', 4);
  const opponent = action('right', 2, 'Decay', 3);
  hook.renderActions([action('left', 1, 'Basic Attack', 0), opponent, player]);
  assert.equal(left.nodes['[data-stage-skill-name]'].textContent, 'Empower');
  assert.equal(right.nodes['[data-stage-skill-name]'].textContent, 'Decay');
  assert.equal(left.nodes['[data-stage-effects]'].icons.length, 4);
  assert.equal(right.nodes['[data-stage-effects]'].icons.length, 3);

  hook.headline(action('right', 4, 'Bad Juju', 5));
  assert.equal(left.nodes['[data-stage-skill-name]'].textContent, 'Empower');
  assert.equal(left.nodes['[data-stage-effects]'].icons.length, 4);
  assert.equal(right.nodes['[data-stage-skill-name]'].textContent, 'Bad Juju');
  assert.equal(right.nodes['[data-stage-summary]'].textContent, '−40');
  assert.equal(right.nodes['[data-stage-summary]']['aria-label'], 'right used Bad Juju');
  assert.equal(right.nodes['[data-stage-effects]'].icons[0].title, '<h3>Effect 0</h3>Triggered 0');
  assert.equal(right.nodes['[data-stage-effects]'].icons.length, 5);

  assert.equal(right.nodes['[data-stage-effects]'].icons[4].image.alt, 'Effect 4');

  hook.activeEffects.left = [
    {code: 'empower', name: 'Empower', duration: 2, tooltip: '2 turns remaining'},
    {code: 'shuriken_toss', name: 'Shuriken Toss', image: 'shuriken.png', duration: 1, kind: 'debuff', description: '1 turn remaining', tooltip: '1 turn remaining'}
  ];
  hook.renderAction('left', player);
  assert.equal(left.nodes['[data-skill-duration]'].textContent, 2);
  assert.equal(left.nodes['[data-stage-effects]'].icons.length, 5);
  const debuff = left.nodes['[data-stage-effects]'].icons[4];
  assert.equal(debuff.image.alt, 'Shuriken Toss');
  assert.equal(debuff.badge.textContent, 1);
  assert.equal(debuff.dataset.kind, 'debuff');
  assert.equal(right.nodes['[data-stage-effects]'].icons.length, 5);
  hook.activeEffects.left = [];
  hook.renderEffectIcons('left');
  assert.equal(left.nodes['[data-skill-duration]'].hidden, true);
  assert.equal(left.nodes['[data-stage-effects]'].icons.length, 4);

  hook.renderAction('right', {...opponent, damage: 0, flag: 'Evaded'});
  assert.equal(right.nodes['[data-stage-summary]'].textContent, 'EVADED');
  assert.equal(right.nodes['[data-stage-summary]'].dataset.outcome, 'evaded');
  assert.equal(right.nodes['[data-stage-flag]'].textContent, '');
  hook.renderAction('right', {...opponent, damage: 20, flag: 'Evaded'});
  assert.equal(right.nodes['[data-stage-summary]'].textContent, '−20');
  assert.equal(right.nodes['[data-stage-flag]'].textContent, 'Evaded');

  hook.renderActions([]);
  for (const side of [left, right]) {
    assert.equal(side.nodes['.stage-ability-ring'].hidden, true);
    assert.equal(side.nodes['[data-stage-skill-name]'].textContent, 'No action yet');
    assert.deepEqual(side.nodes['[data-stage-effects]'].icons, []);
  }
});

test('navigation cancels animations and releases pending waits without playing queued turns', async () => {
  let cancelled = 0;
  let cleared = 0;
  const hook = Object.assign({}, CombatStage, {
    epoch: 0, busy: true, queue: [{number: 2}],
    animations: new Set([{cancel() { cancelled++; }}]),
    waits: new Map(),
    el: {dataset: {}, querySelector: () => ({replaceChildren() { cleared++; }})}
  });
  const waiting = hook.wait(60000);
  hook.cancel();
  await waiting;
  assert.equal(cancelled, 1);
  assert.equal(cleared, 1);
  assert.equal(hook.epoch, 1);
  assert.equal(hook.waits.size, 0);
  assert.deepEqual(hook.queue, []);
  assert.equal(hook.busy, false);
});

test('build cooldown badges update skills and items independently on both sides and disappear when ready', () => {
  const tile = code => ({
    dataset: {buildCode: code}, badge: {},
    querySelector() { return this.badge; }
  });
  const left = [tile('omnislash'), tile('dagon'), tile('empower')];
  const right = [tile('laguna_blade'), tile('dagon')];
  const hook = Object.assign({}, CombatStage, {
    el: {querySelectorAll: selector => selector.includes('left') ? left : right}
  });
  hook.renderBuildCooldowns('left', {omnislash: 3, dagon: 1});
  hook.renderBuildCooldowns('right', {laguna_blade: 2, dagon: 4});
  assert.deepEqual(left.map(t => t.badge.textContent), [3, 1, 0]);
  assert.deepEqual(right.map(t => t.badge.textContent), [2, 4]);
  assert.equal(left[0].dataset.cooling, 'true');
  assert.equal(left[2].badge.hidden, true);

  hook.renderBuildCooldowns('left', {omnislash: 2, dagon: 0});
  assert.equal(left[0].badge.textContent, 2);
  assert.equal(left[1].badge.hidden, true);
  assert.equal(left[1].dataset.cooling, 'false');
  assert.equal(right[1].badge.textContent, 4);

  hook.renderBuildCooldowns('right', {});
  assert.ok(right.every(t => t.badge.hidden && t.dataset.cooling === 'false'));
  hook.renderBuildCooldowns('left');
  assert.ok(left.every(t => t.badge.hidden));
});

test('altered combat stats glow by modifier and pulse only when their displayed values change', t => {
  const original = globalThis.document;
  globalThis.document = {hidden: false};
  t.after(() => { globalThis.document = original; });
  const stat = (key, value, modifier = 0) => ({key, value, modifier, tooltip: `${key}: ${value}`});
  const makeBadge = value => {
    const total = {};
    const modifier = {dataset: {}};
    return {dataset: {statTotal: String(value), statDelta: '0'}, total, modifier,
      querySelector: selector => selector === '[data-stat-value]' ? total : modifier};
  };
  const badges = {attack: makeBadge(100), power: makeBadge(20), armor: makeBadge(10), speed: makeBadge(100)};
  const pulses = [];
  const fighter = {querySelector: selector => badges[selector.match(/data-combat-stat="(\w+)"/)[1]]};
  const hook = Object.assign({}, CombatStage, {motion: {matches: false}, animate: (...args) => pulses.push(args)});
  const changed = [stat('attack', 130, 30), stat('power', 20), stat('armor', -5, -15), stat('speed', 120)];
  hook.renderCombatStats(fighter, changed);
  assert.equal(badges.attack.dataset.statState, 'buff');
  assert.equal(badges.attack.total.textContent, 130);
  assert.equal(badges.attack.modifier.textContent, '+30');
  assert.equal(badges.armor.dataset.statState, 'debuff');
  assert.equal(badges.armor.modifier.textContent, '-15');
  assert.deepEqual(pulses.map(pulse => pulse[0]), [badges.attack, badges.armor]);

  hook.renderCombatStats(fighter, changed);
  assert.equal(pulses.length, 2, 'Duplicate updates must not retrigger pulses');
  hook.renderCombatStats(fighter, [stat('attack', 100)]);
  assert.equal(badges.attack.dataset.statState, 'normal');
  assert.equal(badges.attack.modifier.hidden, true);
  assert.equal(pulses.length, 3, 'Expiry also draws attention to the changed total');

  hook.motion.matches = true;
  hook.renderCombatStats(fighter, [stat('armor', 10)]);
  assert.equal(badges.armor.dataset.statState, 'normal');
  assert.equal(pulses.length, 3);
  hook.motion.matches = false;
  globalThis.document.hidden = true;
  hook.renderCombatStats(fighter, [stat('power', 25, 5)]);
  assert.equal(badges.power.dataset.statState, 'buff');
  assert.equal(pulses.length, 3);
});

test('stun, silence and disarm artwork states stay distinct, clear on expiry and stop on death', () => {
  const fighter = () => ({
    dataset: {}, labels: {stunned: {}, silenced: {}, disarmed: {}},
    querySelector(selector) { return this.labels[selector.match(/data-control-label="(\w+)"/)[1]]; }
  });
  const left = fighter();
  const right = fighter();
  CombatStage.renderControlStatuses(left, {hp: 100, statuses: {stunned: true, silenced: false}});
  CombatStage.renderControlStatuses(right, {hp: 200, statuses: {stunned: false, silenced: true}});
  assert.deepEqual(left.dataset, {stunned: 'true', silenced: 'false', disarmed: 'false'});
  assert.deepEqual(right.dataset, {stunned: 'false', silenced: 'true', disarmed: 'false'});
  assert.equal(left.labels.stunned.hidden, false);
  assert.equal(left.labels.silenced.hidden, true);
  assert.equal(right.labels.silenced.hidden, false);

  CombatStage.renderControlStatuses(left, {hp: 100, statuses: {stunned: true, silenced: true, disarmed: true}});
  assert.ok(Object.values(left.labels).every(label => !label.hidden));
  CombatStage.renderControlStatuses(left, {hp: 100, statuses: {stunned: false, silenced: false}});
  assert.ok(Object.values(left.labels).every(label => label.hidden));
  assert.equal(right.dataset.silenced, 'true');
  CombatStage.renderControlStatuses(left, {hp: 100, statuses: {disarmed: true}});
  assert.equal(left.dataset.disarmed, 'true');
  assert.equal(left.labels.disarmed.hidden, false);
  assert.equal(left.labels.stunned.hidden, true);
  CombatStage.renderControlStatuses(right, {hp: 0, statuses: {stunned: true, silenced: true, disarmed: true}});
  assert.deepEqual(right.dataset, {stunned: 'false', silenced: 'false', disarmed: 'false'});
  assert.ok(Object.values(right.labels).every(label => label.hidden));
});

test('central battle log control stays in sync and brings expanded turns into view once', t => {
  const originals = {document: globalThis.document, requestAnimationFrame: globalThis.requestAnimationFrame};
  t.after(() => Object.assign(globalThis, originals));
  const frames = [];
  const scrolled = [];
  globalThis.requestAnimationFrame = callback => { frames.push(callback); return frames.length; };
  globalThis.document = {getElementById: () => ({scrollIntoView: options => scrolled.push(options)})};
  const button = { setAttribute(name, value) { this[name] = value; }, getAttribute(name) { return this[name]; }};
  const label = {};
  const count = {};
  const nodes = {'[data-stage-log-toggle]': button, '[data-stage-log-label]': label, '[data-stage-log-count]': count};
  button.querySelector = selector => nodes[selector];
  const hook = Object.assign({}, CombatStage, {
    scene: {finished: false, events: [{number: 1}, {number: 2}]},
    motion: {matches: true},
    el: {dataset: {logExpanded: 'false'}, querySelectorAll: () => [button]}
  });
  hook.renderLogToggle();
  assert.equal(button['aria-expanded'], 'false');
  assert.equal(label.textContent, 'Battle log');
  assert.equal(count.textContent, 2);
  assert.equal(button.disabled, false);
  hook.el.dataset.logExpanded = 'true';
  hook.renderLogToggle();
  assert.equal(button['aria-expanded'], 'true');
  assert.equal(label.textContent, 'Hide battle log');
  assert.equal(frames.length, 1);
  frames[0]();
  assert.deepEqual(scrolled, [{behavior: 'auto', block: 'start'}]);
  hook.renderLogToggle();
  assert.equal(frames.length, 1);
  hook.scene.finished = true;
  hook.renderLogToggle();
  assert.equal(button.disabled, false);
  assert.equal(label.textContent, 'Hide battle log');
  hook.scene.events = [];
  hook.renderLogToggle();
  assert.equal(button.disabled, true);
});

test('reduced motion applies the confirmed resources immediately without animation or audio', async () => {
  const applied = [];
  const hook = Object.assign({}, CombatStage, {
    el: {dataset: {}}, motion: {matches: true},
    headline() {},
    setVitals(side, vitals) { applied.push([side, vitals.hp]); },
    animate() { assert.fail('Reduced motion must skip animation'); },
    tone() { assert.fail('Reduced motion must skip action sounds'); }
  });
  await hook.play({actor: 'left', kind: 'spell', after: {left: {hp: 900}, right: {hp: 0}}}, 1);
  assert.deepEqual(applied, [['left', 900], ['right', 0]]);
});

test('evade highlights only the defending hero with its own artwork and a distinct callout', async t => {
  const original = globalThis.document;
  const created = [];
  globalThis.document = {createElement(tag) { const node = {tag, remove() {}}; created.push(node); return node; }};
  t.after(() => { globalThis.document = original; });
  for (const side of ['left', 'right']) {
    const art = {src: `${side}-hero.jpg`};
    const appended = [];
    const fighter = {querySelector: selector => selector === '.stage-art' ? art : {append: node => appended.push(node)}};
    const animations = [];
    const callouts = [];
    const hook = Object.assign({}, CombatStage, {
      el: {querySelector(selector) { assert.equal(selector, `[data-side="${side}"]`); return fighter; }},
      animate(node) { animations.push(node); return Promise.resolve(); },
      float(...args) { callouts.push(args); }
    });
    hook.evade(side);
    assert.equal(appended[0].src, art.src);
    assert.equal(appended[0].className, 'stage-evade-echo');
    assert.equal(appended[1].className, 'stage-evade-wind');
    assert.ok(animations.includes(art));
    assert.deepEqual(callouts, [[side, 'EVADED', 'evade']]);
  }
});

test('duel clock follows the server deadline through turns, urgency and completion', t => {
  const original = {now: Date.now, setInterval: globalThis.setInterval, clearInterval: globalThis.clearInterval};
  t.after(() => { Date.now = original.now; globalThis.setInterval = original.setInterval; globalThis.clearInterval = original.clearInterval; });
  let now = 100000;
  Date.now = () => now;
  const intervals = new Map();
  let nextId = 0;
  globalThis.setInterval = callback => { intervals.set(++nextId, callback); return nextId; };
  globalThis.clearInterval = id => intervals.delete(id);
  const seconds = {}, owner = {};
  const clock = {dataset: {}, querySelector: selector => selector === '[data-stage-clock-seconds]' ? seconds : owner};
  const hook = Object.assign({}, CombatStage, {
    scene: {turnDeadline: 130000, status: 'Your turn', finished: false},
    el: {querySelector: () => clock}
  });
  hook.renderTurnClock();
  assert.equal(clock.hidden, false);
  assert.equal(seconds.textContent, 30);
  assert.equal(owner.textContent, 'Your turn');
  assert.equal(intervals.size, 1);
  now = 125000; // Catch up after background throttling rather than decrementing a stale counter.
  [...intervals.values()][0]();
  assert.equal(seconds.textContent, 5);
  assert.equal(clock.dataset.urgent, 'true');
  now = 140000;
  hook.renderTurnClock();
  assert.equal(seconds.textContent, 0);
  hook.scene = {turnDeadline: 170000, status: 'Waiting for PDK', finished: false};
  hook.renderTurnClock();
  assert.equal(seconds.textContent, 30);
  assert.equal(clock.dataset.urgent, 'false');
  assert.equal(owner.textContent, 'Waiting for PDK');
  assert.equal(intervals.size, 1);
  hook.scene = {turnDeadline: null, finished: true};
  hook.renderTurnClock();
  assert.equal(clock.hidden, true);
  assert.equal(intervals.size, 0);
});

test('health percentages stay centered and update with each combat state', () => {
  const nodes = new Map();
  const fighter = {dataset: {}, querySelector(selector) {
    if (!nodes.has(selector)) nodes.set(selector, {style: {}, textContent: '', setAttribute() {}});
    return nodes.get(selector);
  }};
  const hook = {...CombatStage, el: {querySelector: () => fighter}, activeEffects: {},
    renderControlStatuses() {}, renderCombatStats() {}, renderEffectIcons() {}, renderBuildCooldowns() {}};
  const unit = {hp: 35, maxHp: 100, mp: 20, maxMp: 50, activeEffects: [], cooldowns: {}, combatStats: []};
  hook.setVitals('left', unit);
  assert.equal(nodes.get('[data-unit-hp-percent]').textContent, '35%');
  assert.equal(nodes.get('.stage-health-fill').style.width, '35%');
  hook.setVitals('left', {...unit, hp: 0});
  assert.equal(nodes.get('[data-unit-hp-percent]').textContent, '0%');
  assert.equal(fighter.dataset.dead, 'true');
  hook.setVitals('left', {...unit, hp: 1, maxHp: 1000});
  assert.equal(nodes.get('[data-unit-hp-percent]').textContent, '1%');
  hook.setVitals('left', {...unit, hp: 150});
  assert.equal(nodes.get('[data-unit-hp-percent]').textContent, '100%');
});
