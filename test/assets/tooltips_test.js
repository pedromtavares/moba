const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/js/tooltips.js', 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/export function/g, 'function');

function environment() {
  const references = [];
  const created = [];
  let notify;
  let observers = 0;
  const context = {
    document: {body: {}, querySelectorAll: () => references},
    MutationObserver: class {
      constructor(callback) { notify = callback; observers++; }
      observe() {}
    },
    isGameTooltip: () => true,
    tooltipContent: (_reference, title) => title,
    mobileCheck: () => false,
    tippy(targets, options) {
      targets.forEach(reference => {
        const instance = {
          reference, options, state: {isVisible: false}, destroyed: false, hidden: 0, cleared: 0,
          setContent(content) { this.content = content; },
          setProps() {},
          clearDelayTimeouts() { this.cleared++; },
          hide() { this.hidden++; },
          destroy() { this.destroyed = true; delete reference._tippy; options.onDestroy(this); }
        };
        instance.content = options.content(reference);
        reference._tippy = instance;
        created.push(instance);
        options.onCreate(instance);
      });
    }
  };
  vm.createContext(context);
  vm.runInContext(source, context);

  function anchor(title = 'Item details') {
    const attrs = {'title': title, 'data-toggle': 'tooltip'};
    const reference = {
      isConnected: true, visible: true, inTooltip: false,
      closest: () => reference.inTooltip ? {} : null,
      matches: selector => selector !== 'img' && attrs['data-toggle'] === 'tooltip',
      getClientRects: () => reference.visible ? [{}] : [],
      getAttribute: name => attrs[name] ?? null,
      hasAttribute: name => name in attrs,
      removeAttribute: name => { delete attrs[name]; },
      setAttribute: (name, value) => { attrs[name] = value; }
    };
    references.push(reference);
    return reference;
  }
  return {context, created, anchor, removed: () => notify([{removedNodes: [{}]}]), observerCount: () => observers};
}

test('removing a LiveView anchor destroys its popup and releases the instance', () => {
  const env = environment();
  const reference = env.anchor();
  env.context.initTooltips();
  const instance = reference._tippy;
  instance.state.isVisible = true;
  reference.isConnected = false;
  env.removed();
  assert.equal(instance.destroyed, true);
  env.context.hideTooltips();
  assert.equal(instance.hidden, 0);
});

test('updates reuse anchors, refresh their content, and clean up hidden or disabled tooltips', () => {
  const env = environment();
  const reference = env.anchor();
  env.context.initTooltips();
  const instance = reference._tippy;
  reference.setAttribute('title', 'Updated item');
  env.context.initTooltips();
  assert.equal(env.created.length, 1);
  assert.equal(env.observerCount(), 1);
  assert.equal(instance.content, 'Updated item');
  instance.state.isVisible = true;
  reference.visible = false;
  env.context.initTooltips();
  assert.equal(instance.destroyed, true);
  const replacement = reference._tippy;
  assert.equal(replacement.content, 'Updated item');
  reference.removeAttribute('data-toggle');
  env.context.initTooltips();
  assert.equal(replacement.destroyed, true);
});

test('popup content is not initialized as a new anchor and invisible anchors cannot show', () => {
  const env = environment();
  env.anchor().inTooltip = true;
  const reference = env.anchor();
  env.context.initTooltips();
  assert.equal(env.created.length, 1);
  const instance = reference._tippy;
  assert.equal(instance.options.onShow(instance), true);
  reference.visible = false;
  assert.equal(instance.options.onShow(instance), false);
  reference.visible = true;
  reference.isConnected = false;
  assert.equal(instance.options.onShow(instance), false);
});

test('navigation hides popups and cancels delayed opens', () => {
  const env = environment();
  const reference = env.anchor();
  env.context.initTooltips();
  env.context.hideTooltips();
  assert.equal(reference._tippy.hidden, 1);
  assert.equal(reference._tippy.cleared, 1);
});
