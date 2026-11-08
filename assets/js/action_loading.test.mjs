import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('./action_loading.js', import.meta.url), 'utf8');
const {initActionLoading} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function page() {
  const handlers = {};
  globalThis.document = {addEventListener: (name, handler) => { handlers[name] = handler; }};
  initActionLoading();
  return {
    push(target, event, eventType = 'click', loadingElements = [target]) {
      let reply;
      const loadingComplete = new Promise(resolve => { reply = resolve; });
      handlers['phx:push']({target, detail: {event, eventType, loadingElements, loadingComplete}});
      return async () => { reply(); await loadingComplete; };
    },
    click(target) {
      let prevented = false;
      handlers.click({
        target,
        preventDefault: () => { prevented = true; },
        stopImmediatePropagation: () => {}
      });
      return prevented;
    }
  };
}

function button({id = '', width = 120, community = false, attributes = {}} = {}) {
  const control = {
    id,
    dataset: {},
    textContent: 'Original label',
    matches: selector => selector !== 'form',
    closest: selector => selector === '.community' ? (community ? control : null) : control,
    classList: {contains: () => false},
    getBoundingClientRect: () => ({width}),
    getAttribute: name => attributes[name] ?? null,
    setAttribute: (name, value) => { attributes[name] = value; },
    removeAttribute: name => { delete attributes[name]; }
  };
  return control;
}

test('battle log shows one verb without replacing content and rejects repeat clicks until the reply', async () => {
  const live = page();
  const log = button({id: 'combat-log-toggle', width: 34, attributes: {'aria-expanded': 'false'}});
  const reply = live.push(log, 'toggle-combat-log');
  assert.equal(log.dataset.actionLoading, 'Opening…');
  assert.equal(log.textContent, 'Original label');
  assert.equal(log.getAttribute('aria-busy'), 'true');
  assert.equal(live.click(log), true);
  await reply();
  assert.equal(log.dataset.actionLoading, undefined);
  assert.equal(log.getAttribute('aria-busy'), null);
  assert.equal(live.click(log), false);
});

test('form submits mark the submitter and leave Community alone', async () => {
  const live = page();
  const submit = button();
  const form = {
    matches: selector => selector === 'form',
    closest: () => null,
    querySelector: () => submit
  };
  submit.form = form;
  const reply = live.push(form, 'finish-transmute', 'submit', [submit, form]);
  assert.equal(submit.dataset.actionLoading, 'Transmuting…');
  await reply();
  const community = button({community: true});
  await live.push(community, 'delete-message')();
  assert.equal(community.dataset.actionLoading, undefined);
});

test('quick selections keep their labels and stay pending until the newest reply', async () => {
  const live = page();
  const item = button({width: 40});
  const earlier = live.push(item, 'select-shop');
  const latest = live.push(item, 'select-shop');
  assert.equal(item.dataset.actionLoading, '');
  assert.equal(live.click(item), false);
  await earlier();
  assert.equal(item.getAttribute('aria-busy'), 'true');
  await latest();
  assert.equal(item.getAttribute('aria-busy'), null);
});

test('hook-driven attacks use the same loading feedback', async () => {
  const live = page();
  const attack = button({id: 'attack-button'});
  const reply = live.push(attack, 'next-turn', 'hook');
  assert.equal(attack.dataset.actionLoading, 'Attacking…');
  await reply();
  assert.equal(attack.dataset.actionLoading, undefined);
});
