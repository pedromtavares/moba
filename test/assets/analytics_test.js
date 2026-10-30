const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/analytics.js', 'utf8').replace('export function', 'function');

function environment(id) {
  const scripts = [];
  const document = {
    querySelector: () => id ? {content: id} : null,
    getElementById: name => scripts.find(script => script.id === name),
    createElement: () => ({}),
    head: {appendChild: script => scripts.push(script)}
  };
  const context = {document, window: {}, Date, encodeURIComponent};
  vm.createContext(context);
  vm.runInContext(source, context);
  return {context, scripts};
}

test('disabled or invalid configuration makes no tracking requests', () => {
  for (const id of [null, '', 'UA-123-1', '<script>', 'G-ABC&redirect=evil']) {
    const {context, scripts} = environment(id);
    context.initAnalytics();
    assert.equal(scripts.length, 0);
    assert.equal(context.window.dataLayer, undefined);
  }
});

test('valid configuration loads Google once and uses its automatic page-view tracking', () => {
  const {context, scripts} = environment('G-TEST123456');
  context.initAnalytics();
  context.initAnalytics();
  assert.equal(scripts.length, 1);
  assert.equal(scripts[0].src, 'https://www.googletagmanager.com/gtag/js?id=G-TEST123456');
  assert.equal(scripts[0].async, true);
  const commands = Array.from(context.window.dataLayer, args => Array.from(args));
  assert.equal(commands.length, 2);
  assert.equal(commands[0][0], 'js');
  assert.deepEqual(commands[1], ['config', 'G-TEST123456']);
});
