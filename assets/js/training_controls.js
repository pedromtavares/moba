const typing = "input, textarea, select, [role='textbox'], [role='switch'], [role='slider'], [contenteditable]:not([contenteditable='false'])";
const dialogs = "dialog[open], [role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal";
const visible = element => element && element.getClientRects().length > 0;
const available = element => visible(element) && !element.disabled && element.getAttribute('aria-disabled') !== 'true';

export function initTrainingControls(requestFullscreen = () => {}) {
  let selected = null;
  let hero = null;

  function hud() {
    return Array.from(document.querySelectorAll('.game-page .hero-bar')).find(visible);
  }

  function cards() {
    return Array.from(document.querySelectorAll('.game-page .training-target'))
      .filter(card => available(card.querySelector('.target-battle[phx-click="battle"]')));
  }

  function select(card) {
    selected = card?.id || null;
    document.querySelectorAll('.game-page .training-target')
      .forEach(target => target.classList.toggle('is-keyboard-selected', target === card));
  }

  function refresh() {
    const list = cards();
    const currentHero = hud()?.querySelector('[data-inventory-order]')?.dataset.heroId;
    const current = currentHero === hero && list.find(card => card.id === selected);
    hero = currentHero;
    select(current || list[0]);
    return list;
  }

  function battle(button) {
    if (!available(button)) return;
    requestFullscreen();
    button.click();
  }

  document.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    const card = event.target.closest('.game-page .training-target');
    if (!card || !visible(hud())) return;
    const list = refresh();
    if (!list.includes(card)) return;
    select(card);
    if (event.target.closest('button, a, input, select, textarea') || window.getSelection()?.toString()) return;
    event.preventDefault();
    battle(card.querySelector('.target-battle[phx-click="battle"]'));
  });

  document.addEventListener('keydown', event => {
    const key = event.key.toLowerCase();
    const switchingHero = ['1', '2', '3'].includes(key);
    if (event.defaultPrevented || event.repeat || event.isComposing || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey ||
        event.target.closest(typing)) return;
    if (Array.from(document.querySelectorAll(dialogs)).filter(visible)
      .some(dialog => !switchingHero || !dialog.classList?.contains('shop-modal'))) return;
    const bar = hud();
    if (!visible(bar) || document.querySelector('#battle-page')) return;

    let control;
    if (switchingHero) {
      control = document.querySelector(`#team-select-${key}`);
    } else if (['q', 'w', 'e', 'r'].includes(key)) {
      control = bar.querySelector(`[data-hud-skill-index="${['q', 'w', 'e', 'r'].indexOf(key)}"] .hud-upgrade`);
    } else if (key === 'f') {
      control = Array.from(bar.querySelectorAll('.toggle-shop')).find(available);
    } else if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) {
      const list = refresh();
      if (!list.length) return;
      const index = list.findIndex(card => card.id === selected);
      const direction = ['ArrowLeft', 'ArrowUp'].includes(event.key) ? -1 : 1;
      select(list[(index + direction + list.length) % list.length]);
      list.find(card => card.id === selected).querySelector('.target-battle[phx-click="battle"]').focus({preventScroll: true});
      event.preventDefault();
      return;
    } else if (event.code === 'Space') {
      if (event.target.closest('button, a, summary, [role="button"]')) return;
      const skillGuide = Array.from(document.querySelectorAll('.training .league-skill-warning')).find(available);
      if (skillGuide) {
        event.preventDefault();
        skillGuide.click();
        return;
      }
      const list = refresh();
      control = list.find(card => card.id === selected)?.querySelector('.target-battle[phx-click="battle"]') ||
        Array.from(document.querySelectorAll('.training .ascent-challenge')).find(available);
      if (!available(control)) return;
      event.preventDefault();
      battle(control);
      return;
    }
    if (!available(control)) return;
    event.preventDefault();
    control.click();
  });

  document.addEventListener('phx:update', refresh);
  document.addEventListener('team:hero-switched', () => requestAnimationFrame(() => {
    refresh();
    const shop = hud()?.querySelector('.shop-modal.d-block');
    if (visible(shop)) {
      const selected = shop.querySelector('.shop-tile[aria-pressed=true]:not([aria-disabled=true])') ||
        shop.querySelector('.shop-shelf-label[aria-pressed=true]');
      selected?.focus({preventScroll: true});
    }
  }));
  window.addEventListener('phx:page-loading-stop', refresh);
  refresh();
}
