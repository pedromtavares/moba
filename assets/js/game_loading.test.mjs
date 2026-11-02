import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const source = await readFile(new URL('./game_loading.js', import.meta.url), 'utf8');
const {initGameLoading, loadingTarget} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function setup(t) {
  const originals = Object.fromEntries(['window', 'document', 'setInterval', 'clearInterval', 'setTimeout', 'clearTimeout'].map(key => [key, globalThis[key]]));
  t.after(() => Object.assign(globalThis, originals));
  const element = () => ({
    inert: false, hidden: true, dataset: {}, style: {setProperty() {}}, attributes: new Map(),
    getAttribute(name) { return this.attributes.get(name) ?? null; },
    setAttribute(name, value) { this.attributes.set(name, value); },
    removeAttribute(name) { this.attributes.delete(name); }
  });
  const main = element();
  const nodes = Object.fromEntries(['game-loading-screen', 'game-loading-fill', 'game-loading-progress', 'game-loading-icon', 'game-loading-title', 'game-loading-subtitle', 'game-loading-art', 'game-loading-opponent'].map(id => [id, element()]));
  nodes['main-wrapper'] = main;
  const listeners = {};
  const clicks = [];
  const timers = new Map();
  let nextTimer = 0;
  globalThis.window = {location: new URL('http://localhost/battles/1'), getComputedStyle: node => ({backgroundImage: node.background || 'none', getPropertyValue: () => ''}), addEventListener(name, callback) { listeners[name] = callback; }};
  globalThis.document = {getElementById: id => nodes[id], querySelector: () => null, addEventListener(name, callback, capture) { if (name === 'click') clicks[capture ? 0 : 1] = callback; }};
  globalThis.setInterval = () => ++nextTimer;
  globalThis.clearInterval = () => {};
  globalThis.setTimeout = callback => { const id = ++nextTimer; timers.set(id, callback); return id; };
  globalThis.clearTimeout = id => timers.delete(id);
  initGameLoading();
  return {
    main, nodes, element,
    click(control, options = {}) { const event = {button: 0, target: {closest: () => control}, ...options}; clicks.forEach(callback => callback(event)); },
    emit(name, detail) { listeners[name]({detail}); },
    complete() { [...timers.values()].forEach(callback => callback()); timers.clear(); }
  };
}

test('returning from battle releases the outer wrapper when training restores the sidebar', t => {
  const page = setup(t);
  const transition = {kind: 'redirect', to: '/training'};
  page.emit('phx:page-loading-start', transition);
  assert.equal(page.main.inert, true);
  page.nodes['game-content'] = page.element();
  page.emit('phx:page-loading-stop', transition);
  page.complete();
  assert.equal(page.main.inert, false);
  assert.equal(page.main.getAttribute('aria-busy'), null);
  assert.equal(page.nodes['game-content'].inert, false);
  assert.equal(page.nodes['game-loading-screen'].hidden, true);
});

test('overlapping loads release every original container and preserve its prior accessibility state', t => {
  const page = setup(t);
  const initial = {kind: 'initial'};
  const redirect = {kind: 'redirect', to: '/training'};
  page.main.setAttribute('aria-busy', 'false');
  page.emit('phx:page-loading-start', initial);
  const content = page.element();
  content.inert = true;
  content.setAttribute('aria-busy', 'true');
  page.nodes['game-content'] = content;
  page.emit('phx:page-loading-start', redirect);
  page.emit('phx:page-loading-stop', initial);
  assert.equal(page.main.inert, true);
  page.emit('phx:page-loading-stop', redirect);
  page.complete();
  assert.equal(page.main.inert, false);
  assert.equal(page.main.getAttribute('aria-busy'), 'false');
  assert.equal(content.inert, true);
  assert.equal(content.getAttribute('aria-busy'), 'true');
});

test('a failed navigation also releases the original container after a layout change', t => {
  const page = setup(t);
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/training'});
  page.nodes['game-content'] = page.element();
  page.emit('phx:page-loading-start', {kind: 'error'});
  assert.equal(page.main.inert, false);
  assert.equal(page.nodes['game-loading-screen'].hidden, true);
});

// Small DOM fixtures keep these tests independent of a browser or a server.
function node({text = '', attrs = {}, children = {}, closest = {}, background = 'none'} = {}) {
  return {
    textContent: text, background, alt: attrs.alt || '', href: attrs.href,
    getAttribute: name => attrs[name] ?? null,
    hasAttribute: name => Object.hasOwn(attrs, name),
    closest: selector => closest[selector] || null,
    querySelector: selector => children[selector] || null,
    querySelectorAll: selector => children[selector] || [],
    matches: () => false
  };
}

test('a training launch carries the rendered opponent through navigation and nested joins', t => {
  const page = setup(t);
  const card = node({background: 'url("/already-rendered/puck.jpg")', children: {
    '.target-name': node({text: 'Puck'}), '.target-level-value': node({text: '12'})
  }});
  const control = node({attrs: {'phx-click': 'battle'}, closest: {'.training-target': card}});
  page.click(control);
  assert.equal(page.nodes['game-loading-screen'].hidden, true, 'wait for a real navigation, not just a click');
  const navigation = {kind: 'redirect', to: '/battles/12'};
  page.emit('phx:page-loading-start', navigation);
  assert.equal(page.nodes['game-loading-title'].textContent, 'Puck');
  assert.equal(page.nodes['game-loading-subtitle'].textContent, 'Level 12 · Training battle');
  assert.equal(page.nodes['game-loading-icon'].src, '/already-rendered/puck.jpg');
  assert.equal(page.nodes['game-loading-art'].src, '/already-rendered/puck.jpg');
  const join = {kind: 'initial'};
  page.emit('phx:page-loading-start', join);
  assert.equal(page.nodes['game-loading-title'].textContent, 'Puck');
  page.emit('phx:page-loading-stop', navigation);
  assert.equal(page.nodes['game-loading-screen'].dataset.state, 'loading');
  page.emit('phx:page-loading-stop', join);
  page.complete();
  assert.equal(page.main.inert, false);
});

test('unrelated destinations, rejected launches and modified clicks cannot reuse a stale opponent', t => {
  const page = setup(t);
  const row = node({children: {'.arena-live-opponent-identity strong': node({text: 'PDK'})}});
  const control = node({attrs: {'phx-click': 'challenge'}, closest: {li: row}});
  page.click(control);
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/community'});
  assert.equal(page.nodes['game-loading-title'].hidden, true);
  assert.equal(page.nodes['game-loading-icon'].src, '/images/navigation/community.webp');
  page.emit('phx:page-loading-start', {kind: 'error'});
  page.click(control, {ctrlKey: true});
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/arena/12'});
  assert.equal(page.nodes['game-loading-title'].hidden, true);
  page.emit('phx:page-loading-start', {kind: 'error'});
  page.click({...control, disabled: true});
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/arena/12'});
  assert.equal(page.nodes['game-loading-title'].hidden, true);
});

test('replays show both known heroes and clear them for the next ordinary destination', t => {
  const page = setup(t);
  const row = node({children: {'.match-summary-hero img, .duel-survivor img, .match-battle-hero img': [
    node({attrs: {src: '/axe.png', alt: 'Axe'}}), node({attrs: {src: '/puck.png', alt: 'Puck'}})
  ]}});
  const control = node({attrs: {href: 'http://localhost/battles/7', 'data-phx-link': 'redirect'},
    closest: {'.match-summary-row, .duel-round-battle, .match-battle': row}});
  page.click(control);
  const navigation = {kind: 'redirect', to: '/battles/7'};
  page.emit('phx:page-loading-start', navigation);
  assert.equal(page.nodes['game-loading-title'].textContent, 'Axe vs Puck');
  assert.equal(page.nodes['game-loading-opponent'].src, '/puck.png');
  assert.equal(page.nodes['game-loading-opponent'].hidden, false);
  page.emit('phx:page-loading-stop', navigation);
  page.complete();
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/library'});
  assert.equal(page.nodes['game-loading-title'].hidden, true);
  assert.equal(page.nodes['game-loading-opponent'].hidden, true);
  assert.equal(page.nodes['game-loading-art'].hidden, true);
});

test('returning to training uses the owned hero even when that hero is on the right', t => {
  setup(t);
  const scene = {dataset: {scene: JSON.stringify({units: [
    {you: false, avatar: 'Puck', art: '/puck.jpg'},
    {you: true, avatar: 'Axe', portrait: '/axe.png', art: '/axe.jpg'}
  ]})}};
  const target = loadingTarget(null, '/training', {querySelector: selector => selector === '#combat-stage' ? scene : null});
  assert.equal(target.name, 'Axe');
  assert.equal(target.art, '/axe.jpg');
});

test('matchmaking reports the mode without inventing an opponent and missing images fall back', t => {
  const page = setup(t);
  page.click(node({attrs: {'phx-click': 'season-duel'}}));
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/arena/9'});
  assert.equal(page.nodes['game-loading-title'].textContent, '1v1');
  assert.equal(page.nodes['game-loading-subtitle'].textContent, 'Finding your opponent');
  page.nodes['game-loading-icon'].onerror();
  assert.equal(page.nodes['game-loading-icon'].src, '/images/navigation/arena.webp');
});

test('league challenges and Roshan use the visible emblem or boss, with no opponent lookup', t => {
  setup(t);
  const emblem = node({attrs: {src: '/images/league/3.png'}});
  const ascent = node({children: {'.is-next .ascent-rank-name': node({text: 'Platinum'}), '.is-next img': emblem}});
  const league = loadingTarget(node({attrs: {'phx-click': 'league'}, closest: {'#training-ascent': ascent}}));
  assert.equal(league.name, 'Platinum');
  assert.equal(league.image, '/images/league/3.png');
  const boss = node({children: {'#roshan-title': node({text: 'Roshan'}), '.roshan-attempt': node({text: 'Attempt 2 / 2'}),
    '.roshan-portrait': node({background: 'url("/roshan.jpg")'})}});
  const roshan = loadingTarget(node({attrs: {'phx-click': 'league'}, closest: {'#roshan-challenge': boss}}));
  assert.equal(roshan.name, 'Roshan');
  assert.equal(roshan.subtitle, 'Attempt 2 / 2');
  assert.equal(roshan.art, '/roshan.jpg');
});

test('hero links use the card art rather than a skill icon, and profile labels omit activity text', t => {
  setup(t);
  const card = node({background: 'url("/juggernaut.jpg")', children: {
    '.hero-card-name, .hero-name, #hero-detail-name, strong': node({text: 'Aether'}),
    '.hero-card-meta, .hero-detail-avatar-name, small, .profile-featured-heading span[data-toggle]': node({text: 'Level 12 Juggernaut'})
  }});
  const hero = loadingTarget(node({closest: {'.hero-card, .profile-featured, .profile-debut-hero': card}}), '/hero/7');
  assert.equal(hero.name, 'Aether');
  assert.equal(hero.art, '/juggernaut.jpg');
  assert.equal(hero.image, '');
  const player = loadingTarget(node({text: 'PDK 54 AR Active now', children: {
    'strong, .profile-ranked-name': node({text: 'PDK'})
  }}), '/player/2');
  assert.equal(player.name, 'PDK');
  assert.deepEqual(player, {name: 'PDK', simple: true});
});

test('local actions never borrow the current profile identity', t => {
  setup(t);
  window.location = new URL('http://localhost/player/2');
  const target = loadingTarget(node({text: '1v1', attrs: {'phx-click': 'history-tab'}}));
  assert.equal(target, null);
});


test('profile transitions show only the username and clear richer previous targets', t => {
  const page = setup(t);
  const control = node({text: 'PDK', attrs: {href: 'http://localhost/player/2', 'data-phx-link': 'redirect'}});
  page.click(control);
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/player/2'});
  assert.equal(page.nodes['game-loading-title'].textContent, 'PDK');
  assert.equal(page.nodes['game-loading-screen'].dataset.simple, 'true');
  assert.equal(page.nodes['game-loading-subtitle'].hidden, true);
  assert.equal(page.nodes['game-loading-art'].hidden, true);
  assert.equal(page.nodes['game-loading-opponent'].hidden, true);
  page.emit('phx:page-loading-start', {kind: 'redirect', to: '/tavern'});
  assert.equal(page.nodes['game-loading-screen'].dataset.simple, 'false');
});
