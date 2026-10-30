import Shepherd from 'shepherd.js';

const chapters = ['Training', 'Base'];

const chapterTrack = chapter => `<div class="tutorial-chapters" aria-label="Tutorial chapters">${chapters.map((name, index) =>
  `<span class="${index === chapter ? 'is-current' : index < chapter ? 'is-complete' : ''}"><b>0${index + 1}</b> ${name}</span>`
).join('')}</div>`;

const facts = entries => `<div class="tutorial-facts">${entries.map(([value, label, tone]) =>
  `<div data-tone="${tone || 'gold'}"><strong>${value}</strong><span>${label}</span></div>`
).join('')}</div>`;

const goals = entries => `<ol class="tutorial-goals">${entries.map(([title, text], index) =>
  `<li><span>0${index + 1}</span><div><strong>${title}</strong><p>${text}</p></div></li>`
).join('')}</ol>`;

const shopRecommendations = () => `<div class="tutorial-shop-items">${[
  ['boots_of_speed', 'Boots of Speed'], ['sages_mask', 'Sage’s Mask']
].map(([code, name]) => `<div><img src="${document.querySelector(`.normal-items .code-${code}`)?.src || ''}" alt="" /><strong>${name}</strong></div>`).join('')}</div>`;

const ModernTutorial = {
  start(hook, step) {
    this.stop(hook);
    Shepherd.activeTour && Shepherd.activeTour.complete();
    const chapter = step >= 20 ? 1 : 0;
    const interactive = [1, 3, 4, 6, 7, 8, 9].includes(step);
    const tour = new Shepherd.Tour({
      tourName: 'game-field-guide',
      useModalOverlay: !interactive,
      keyboardNavigation: false,
      defaultStepOptions: {
        classes: 'tutorial-hud',
        cancelIcon: { enabled: true, label: 'Dismiss guide' },
        scrollTo: { behavior: 'smooth', block: 'center' },
        modalOverlayOpeningPadding: 10,
        modalOverlayOpeningRadius: 8,
        highlightClass: 'tutorial-focus',
        popperOptions: { modifiers: [
          { name: 'offset', options: { offset: [0, 18] } },
          { name: 'preventOverflow', options: { padding: 16, altAxis: true, tether: false, rootBoundary: 'viewport' } }
        ] }
      }
    });
    hook.gameTutorial = tour;
    const cleanup = () => document.body.classList.remove('tutorial-active');
    tour.on('start', () => document.body.classList.add('tutorial-active'));
    tour.on('complete', cleanup);
    tour.on('cancel', cleanup);

    const event = name => () => { tour.complete(); hook.pushEvent(name, {}); };
    const next = () => tour.next();
    const skip = { text: 'Skip tutorial', secondary: true, action: event('finish-tutorial') };
    const button = (text, action) => ({ text, action });
    const targetAction = selector => () => {
      tour.complete();
      document.querySelector(selector)?.click();
    };

    const add = ({ id, title, text, objective, target, on = 'right', art, extra = '', primary, advance, shop = false }) => {
      const anchor = target && document.querySelector(target);
      tour.addStep({
        id: `guide-${step}-${id}`,
        title,
        classes: art ? 'tutorial-cinematic' : shop ? 'tutorial-shop-guide' : '',
        scrollTo: !!anchor,
        attachTo: anchor ? { element: target, on } : undefined,
        advanceOn: advance ? { selector: advance, event: 'click' } : undefined,
        text: `${art ? `<div class="tutorial-art" style="background-image:url('/images/tutorial/${art}.jpg')" aria-hidden="true"></div>` : ''}
          <div class="tutorial-body">${chapterTrack(chapter)}
            <p class="tutorial-eyebrow">${objective || 'Field guide'}</p>
            <h2>${title}</h2><p class="tutorial-lead">${text}</p>${extra}
          </div>`,
        buttons: [skip, ...(primary ? [primary] : [])],
        when: { 'before-show': function () {
          tour.options.useModalOverlay = !!art || !interactive;
          if (anchor && window.innerWidth < 768) this.options.attachTo.on = 'bottom';
        } }
      });
    };

    switch (step) {
      case 1:
        if (!document.querySelector('.targets .battle-button')) break;
        add({ id: 'welcome', art: 'training-gateway', objective: 'A hero is born', title: 'Your legend starts here.',
          text: 'Train your hero. Forge your strategy. Become an Invoker.',
          extra: goals([['Battle', 'Earn experience for levels and power.'], ['Forge', 'Acquire items and transmute them into Legendary gear.'], ['Ascend', 'Challenge your strategy through multiple leagues and Roshan.']]),
          primary: button('Enter training →', next) });
        add({ id: 'first-battle', objective: 'First objective', title: 'Make your first move.',
          text: "Let's put the Hero you created to the test.",
          target: '.targets .battle-button', advance: '.targets .battle-button',
          primary: button('Battle this target →', targetAction('.targets .battle-button')) });
        break;
      case 2:
        add({ id: 'rewards', objective: 'First battle complete', title: 'The climb has begun.',
          text: 'Battles earn the resources that power your build. Meditation earns experience; mining earns gold.<br /><br />Experience is used to level up and become stronger, while Gold is used to buy items in the Shop, in fact, let\'s head there now.',
          extra: facts([['XP', 'Level up & grow stronger', 'blue'], ['Gold', 'Buy & upgrade items']]),
          primary: button('Gear up at the shop →', event('tutorial3')) });
        break;
      case 3:
        add({ id: 'buy', objective: 'Shop · Buy 2 items', title: 'Your first upgrades.', shop: true,
          text: 'Buy two different Normal items. We recommend:',
          target: '.normal-items', extra: shopRecommendations() });
        break;
      case 4:
        add({ id: 'stats', objective: 'Upgrades equipped', title: 'Feel the difference.',
          text: 'Your items are equipped. Inspect the colored stats in your hero bar to see what changed. Keep battling to earn more gold.',
          target: '#current-hero-stats', on: 'top', primary: button('Back to battle →', event('tutorial5')) });
        break;
      case 6:
        add({ id: 'forge', objective: 'Stronger gear', title: 'Item transmutation',
          text: 'Looks like you have enough gold to transmute your first Rare item.',
          extra: facts([['3 Normal', 'Combine into', 'gold'], ['1 Rare', 'Your next upgrade', 'blue']]),
          primary: button('Open Shop →', () => hook.pushEvent('toggle-shop', {}, next)) });
        add({ id: 'third-item', objective: 'Shop · Prepare the recipe', title: 'One more ingredient.', shop: true,
          text: 'Buy one more Normal item. Choose one you don’t already own.',
          target: '.normal-items' });
        break;
      case 7:
        add({ id: 'rare', objective: 'Shop · Choose a Rare item', title: 'Make it Rare.', shop: true,
          text: "Now, pick one of the Rare items and select the 'Transmute' action. We recommend the Tranquil Boots.",
          target: '.rare-items .code-tranquil_boots', on: 'left' });
        break;
      case 8:
        add({ id: 'recipe', objective: 'Shop · Selection', title: 'Three become one.', shop: true,
          text: 'Select your 3 Normal items and then click on Transmute.',
          target: '.inventory-item', on: 'top-start' });
        break;
      case 9:
        add({ id: 'forged', objective: 'Transmutation complete', title: 'First Rare', shop: true,
          text: 'Great! You now have your first Rare item. If you got the Boots, remember to use them during a battle.<br /><br />Also, make sure to come back here and buy a Normal item when you have 400 gold, you can always transmute it into a stronger item later!',
          target: '.inventory-item img', on: 'left', primary: button('Return to battle →', event('close-shop')) });
        break;
      case 11:
        add({ id: 'silver', objective: 'Congratulations', title: 'Silver League. Earned.',
          text: 'Continue battling until you reach at least the Platinum League. Also, remember to keep buying items at the Shop and to level up your skills on the bottom bar. Have fun!',
          extra: '<img class="tutorial-rank" src="/images/league/1.png" alt="Silver League" />',
          primary: button('Continue your ascent →', event('finish-tutorial')) });
        break;
      case 20:
        add({ id: 'base', art: 'hall-of-legends', objective: 'Build a legacy', title: 'One hero is only the beginning.',
          text: 'Welcome to your Base. Every trained Avatar adds to your collection and brings you closer to Invoker.',
          extra: goals([['Collect', 'Train different Avatars and discover new builds.'], ['Master', 'Push your heroes into higher leagues.'], ['Become Invoker', '20 Undefeated Avatars. Perfect runs with no deaths.']]),
          primary: button('Explore your Base →', next) });
        add({ id: 'progression', objective: 'Your long game', title: 'Track your rise.',
          text: 'Your training progression records your highest achievements. Claim new ranks as your collection grows.',
          target: '#pve-progression', on: 'bottom', primary: button('View your collection →', event('tutorial1')) });
        break;
      case 21:
        add({ id: 'collection', objective: 'The ultimate challenge', title: 'A collection of legends.',
          text: 'Reach Invoker by training 20 distinct Avatars to Grandmaster League with at least 60K total farm each. This is the ultimate game objective.<br /><br />Every Avatar brings a different playstyle and Training gets harder (and more fun!) as you rank up.',
          target: '#hero-list-container', on: 'top', extra: facts([['20', 'Distinct Avatars'], ['60K', 'Farm each', 'blue']]),
          primary: button('Next →', next) });
        add({ id: 'account', objective: 'Keep your legacy', title: 'Make it yours.',
          text: document.querySelector('#create-account-link')
            ? 'Keep training for free. Create an account to save your collection and take your trained heroes into the PvP Arena.'
            : 'Your collection is saved to your account. Keep training new Avatars and take your trained heroes into the PvP Arena.',
          target: '#create-account-link', primary: button('Explore the game →', event('finish-tutorial')) });
        break;

    }

    if (tour.steps.length) {
      hook.gameTutorialTimer = setTimeout(() => {
        if (hook.el.isConnected) tour.start();
      }, 350);
    }
  },

  stop(hook) {
    clearTimeout(hook.gameTutorialTimer);
    if (hook.gameTutorial) {
      hook.gameTutorial.complete();
      hook.gameTutorial = null;
    }
  }
};

export default ModernTutorial;
