const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');

const source = readFileSync('assets/js/return_invitation.js', 'utf8')
  .replace('export function', 'function');

function page({token = 'A'.repeat(43), response = {ok: true, json: async () => ({username: 'ReturningHero'})}, fail = false} = {}) {
  const nodes = Object.fromEntries([
    'return-invitation-form', 'return-enter', 'return-token', 'return-heading',
    'return-description', 'return-status', 'return-login'
  ].map(id => [id, {hidden: false, value: '', textContent: '', disabled: true}]));
  nodes['return-invitation-form'].dataset = {invalid: 'false', checkUrl: '/return/check'};
  const handlers = {};
  nodes['return-invitation-form'].addEventListener = (name, callback) => { handlers[name] = callback; };
  const requests = [];
  const history = [];
  vm.runInNewContext(source + '\ninitReturnInvitation();', {
    URLSearchParams,
    document: {
      getElementById: id => nodes[id],
      querySelector: () => ({content: 'csrf-value'})
    },
    window: {
      location: {hash: token ? '#token=' + token : '', pathname: '/return', reload: () => { handlers.reloaded = true; }},
      addEventListener: (name, callback) => { handlers[name] = callback; },
      history: {replaceState: (...args) => history.push(args)}
    },
    fetch: async (url, options) => {
      requests.push({url, options});
      if (fail) throw new Error('network unavailable');
      return response;
    }
  });
  return {nodes, handlers, requests, history};
}

const flush = () => new Promise(resolve => setImmediate(resolve));

test('removes the secret from history and checks the invitation without redeeming it', async () => {
  const state = page();
  await flush();
  assert.equal(state.history[0][2], '/return');
  assert.equal(state.requests.length, 1);
  assert.equal(state.requests[0].url, '/return/check');
  assert.equal(state.requests[0].options.headers['x-csrf-token'], 'csrf-value');
  assert.equal(state.nodes['return-heading'].textContent, 'Welcome back, ReturningHero.');
  assert.equal(state.nodes['return-enter'].disabled, false);
  assert.equal(state.nodes['return-token'].value, 'A'.repeat(43));
  state.handlers.submit();
  assert.equal(state.nodes['return-enter'].disabled, true);
  assert.equal(state.nodes['return-enter'].textContent, 'Entering…');
});

test('missing or malformed invitations offer normal sign-in without a token request', () => {
  for (const token of ['', 'invalid']) {
    const state = page({token});
    assert.equal(state.requests.length, 0);
    assert.equal(state.nodes['return-invitation-form'].hidden, true);
    assert.equal(state.nodes['return-login'].hidden, false);
    assert.equal(state.nodes['return-token'].value, '');
  }
});

test('expired and already-used tokens have a clear sign-in fallback', async () => {
  const state = page({response: {ok: false, status: 422}});
  await flush();
  assert.equal(state.nodes['return-heading'].textContent, 'Your invitation has expired.');
  assert.equal(state.nodes['return-invitation-form'].hidden, true);
  assert.equal(state.nodes['return-login'].hidden, false);
});

test('a network failure explains how to retry without submitting a token', async () => {
  const state = page({fail: true});
  await flush();
  assert.equal(state.nodes['return-heading'].textContent, 'Your heroes are waiting.');
  assert.equal(state.nodes['return-token'].value, '');
  assert.equal(state.nodes['return-enter'].disabled, true);
});

test('opening another invitation while already on the return page rechecks the new fragment', () => {
  const state = page();
  state.handlers.hashchange();
  assert.equal(state.handlers.reloaded, true);
  assert.equal(state.requests[0].url, '/return/check');
});
