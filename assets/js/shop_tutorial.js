import Shepherd from 'shepherd.js';
import {offset, shift} from '@floating-ui/dom';

// Derive the next action from the rendered inventory, not from optimistic clicks.
// A rejected purchase must keep pointing at Buy, rather than skip an upgrade.
export function shopTutorialAction(step, state) {
  const {owned, selected, selectedRarity, normalItems, inventory, recipe, recipeRarity, recipeCount} = state;
  const choose = (item, caption) => item && ({
    selector: `.normal-items button[phx-value-code="${item.code}"]`,
    title: `Choose ${item.name}`, caption
  });
  const buy = (item, caption) => selected === item.code && state.inspected !== false
    ? {selector: '#buy-button', title: `Buy ${item.name}`, caption}
    : choose(item, caption);

  if (step === 3 || step === 6) {
    if (step === 3 && owned.length >= 2) return null;
    const preferences = step === 3 ? ['boots_of_speed', 'sages_mask'] : ['chainmail'];
    const item = preferences.map(code => normalItems.find(item => item.code === code && !owned.includes(code))).find(Boolean)
      || normalItems.find(item => !owned.includes(item.code));
    const caption = step === 3 ? `Your first upgrades · ${Math.min(owned.length + 1, 2)} of 2` : 'One more item for your first transmute';
    return item ? buy(item, caption) : null;
  }

  if (step === 7) {
    return selectedRarity === 'rare'
      ? {selector: '#start-transmute', title: 'Transmute this Rare item', caption: 'Combine 3 Normal items · no gold needed'}
      : {selector: '.rare-items button[phx-value-code="tranquil_boots"]', title: 'Choose Tranquil Boots', caption: 'Your first Rare item'};
  }

  if (step === 8) {
    const item = inventory.find(item => item.rarity === recipeRarity && !recipe.includes(item.code));
    return recipe.length < recipeCount && item
      ? {selector: `#inventory button[phx-value-code="${item.code}"]`, title: `Add ${item.name}`, caption: `Choose ingredients · ${recipe.length + 1} of ${recipeCount}`}
      : {selector: '#finish-transmute', title: 'Create your Rare item', caption: 'Three items become one'};
  }
  return null;
}

const escapeHTML = text => text.replace(/[&<>"']/g, char => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[char]));

export function startShopTutorial(hook, step) {
  hook.gameShopTutorial?.stop();
  const modal = document.getElementById('shop-modal');
  if (!modal) return;
  const tour = new Shepherd.Tour({
    tourName: 'shop-actions', useModalOverlay: false, keyboardNavigation: false,
    defaultStepOptions: {
      classes: 'tutorial-shop-pointer', scrollTo: false, canClickTarget: true,
      cancelIcon: {enabled: true, label: 'Dismiss guide'},
      highlightClass: 'tutorial-shop-focus',
      floatingUIOptions: {middleware: [offset(18), shift({padding: 12, crossAxis: true, rootBoundary: 'viewport'})]}
    }
  });
  let frame, signature, reference, guide;
  const cleanup = () => {
    cancelAnimationFrame(frame);
    observer.disconnect();
    document.body.classList.remove('tutorial-active');
  };
  tour.on('complete', cleanup);
  tour.on('cancel', cleanup);
  hook.gameShopTutorial = {stop() { tour.complete(); }};

  const refresh = () => {
    const shop = modal.querySelector('#shop');
    if (!shop || !modal.classList.contains('d-block')) {
      tour.hide();
      signature = null;
      return;
    }
    const inventory = [...shop.querySelectorAll('#inventory .inventory-item')].map(el => ({
      code: el.getAttribute('phx-value-code'), name: el.getAttribute('aria-label'), rarity: el.dataset.rarity,
      selected: el.getAttribute('aria-pressed') === 'true'
    }));
    const action = shopTutorialAction(step, {
      owned: inventory.map(item => item.code),
      selected: shop.dataset.selectedCode, selectedRarity: shop.dataset.selectedRarity, inspected: shop.dataset.itemInspected === 'true',
      normalItems: [...shop.querySelectorAll('.normal-items .shop-tile')].map(el => ({code: el.getAttribute('phx-value-code'), name: el.getAttribute('aria-label')})),
      inventory, recipe: inventory.filter(item => item.selected).map(item => item.code),
      recipeRarity: shop.dataset.recipeRarity, recipeCount: Number(shop.dataset.recipeCount)
    });
    const target = action && shop.querySelector(action.selector);
    if (!target || target.getClientRects().length === 0) { tour.hide(); signature = null; return; }
    const nextSignature = JSON.stringify(action);
    if (signature === nextSignature && reference === target) return;
    signature = nextSignature;
    reference = target;
    const options = {
      id: 'shop-next-action',
      label: action.title,
      attachTo: {element: action.selector, on: action.selector.startsWith('#buy') || action.selector.includes('transmute') ? 'top' : 'bottom'},
      text: `<p class="shop-guide-caption">${escapeHTML(action.caption)}</p><strong>${escapeHTML(action.title)}</strong>`,
      buttons: [{text: 'Skip tutorial', secondary: true, action: () => { tour.complete(); hook.pushEvent('finish-tutorial', {}); }}]
    };
    if (guide) { guide.updateStepOptions(options); guide.show(); }
    else { guide = tour.addStep(options); tour.start(); }
    document.body.classList.add('tutorial-active');
  };
  const queueRefresh = () => { cancelAnimationFrame(frame); frame = requestAnimationFrame(refresh); };
  const observer = new MutationObserver(queueRefresh);
  observer.observe(modal, {attributes: true, childList: true, subtree: true});
  queueRefresh();
}
