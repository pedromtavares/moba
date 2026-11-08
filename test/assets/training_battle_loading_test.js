const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/hooks.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^Hooks\.(InvokeStage|CombatStage|InventoryOrder|LineupOrder|ManualCodex) = .*;\n/gm, '')
  .replace('export default Hooks;', 'module.exports = Hooks.Loading;');

function launch(attrs) {
  const listeners = {};
  const sent = [];
  const el = {closest: () => null, getAttribute: key => attrs[key] || null, addEventListener: (name, fn) => { listeners[name] = fn; }};
  const loading = {find: () => [], html: text => { el.loading = text; }};
  const $ = () => ({attr: key => attrs[key], find: () => loading, prop: (key, value) => { el[key] = value; }});
  const context = {module: {exports: {}}, $};
  vm.runInNewContext(source, context);
  const hook = {...context.module.exports, el, pushEvent: (name, payload) => sent.push({name, payload})};
  hook.mounted();
  listeners.click({stopPropagation() {}});
  return {el, sent};
}

test('the battle loading hook forwards the clicked target and hero together, exactly once', () => {
  for (const hero of ['1', '2', '3']) {
    const {el, sent} = launch({'phx-click': 'battle', 'phx-value-id': '7', 'phx-value-hero_id': hero});
    assert.equal(sent.length, 1);
    assert.equal(sent[0].name, 'battle');
    assert.equal(sent[0].payload.id, '7');
    assert.equal(sent[0].payload.hero_id, hero);
    assert.equal(el.loading, undefined);
  }
});

test('league challenges keep their hero context and solo launches omit it', () => {
  const league = launch({'phx-click': 'league', 'phx-value-hero_id': '3'});
  assert.equal(league.sent[0].payload.hero_id, '3');
  const solo = launch({'phx-click': 'battle', 'phx-value-id': '9'});
  assert.equal(Object.hasOwn(solo.sent[0].payload, 'hero_id'), false);
});
