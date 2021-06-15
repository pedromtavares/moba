import Shepherd from 'shepherd.js';
import mobileCheck from "./mobile_check";

const Tutorial = {
  start: function (hookInstance, step) {
    Shepherd.activeTour && Shepherd.activeTour.complete();

    let tour = new Shepherd.Tour(this.tourOptions(step))

    tour = this.tourSteps(tour, step, hookInstance)

    setTimeout(function () {
      if (!mobileCheck()){
        tour.start();
      }
    }, 1000)
  },
  complete: function (hookInstance) {
    if (Shepherd.activeTour) {
      hookInstance.pushEvent("tutorial14", {});
      Shepherd.activeTour.complete();
    }
  },
  tourOptions: function (step) {
    let opts = {
      defaultStepOptions: { scrollTo: false }
    };

    switch (step) {
      case 1: return opts;
      case 3: return opts;
      case 7: return opts;
      case 8: return opts;
      case 9: return opts;
      default: return { ...opts, useModalOverlay: true }
    }
  },
  tourSteps: function (tour, step, hookInstance) {
    switch (step) {
      case 1:
        tour.addStep({
          id: 'first-tutorial-first-step',
          text: "Welcome to the Jungle! Now that you've created your hero, it's time to put it to the test. Gank this target to start your first battle.",
          attachTo: {
            element: '.targets .battle-button',
            on: 'right'
          },
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 25] } }]
          },
          advanceOn: {
            selector: "button", event: "click"
          }
        });
        break;
      case 2:
        tour.addStep({
          id: 'second-tutorial-first-step',
          text: "<h3 class='text-center mb-4'>Congrats on your first battle!</h3><p>Here in the Jungle is where you will farm <span class='text-primary'>Experience</span> and <span class='text-warning'>Gold</span> by ganking other opponents.</p><p><span class='text-primary'>Experience</span> is used to level up and become stronger, while <span class='text-warning'>Gold</span> is used to buy items in the <span class='text-warning'>Shop</span>, in fact, let's head there now.</p>",
          buttons: [
            {
              text: 'Open Shop',
              action: function () { hookInstance.pushEvent("tutorial3", {}); this.complete() }
            }
          ]
        });
        break;
      case 3:
        tour.addStep({
          id: 'third-tutorial-first-step',
          text: "<p class='text-center'>The Shop is where you can spend your <span class='text-warning'>Gold</span>.</p><p class='text-center'>For now, you only have enough to buy 2 <span class='text-dark'>Normal</span> items, we recommend a <span style='color: rosybrown'>Boots of Speed</span> and a <span style='color: mediumpurple'>Sage's Mask</span>.</p>",
          attachTo: {
            element: '.normal-items',
            on: 'right'
          },
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 20] } }]
          },
          cancelIcon: { enabled: true }
        });
        break;
      case 4:
        tour.addStep({
          id: 'fourth-tutorial-first-step',
          text: "<p class='text-center'>Cool, now you're a bit stronger with those items. You can check all of your stats by hovering each of them for more detailed information.</p>",
          attachTo: {
            element: '#current-hero-stats',
            on: 'right'
          },
          buttons: [
            {
              text: 'Next',
              action: tour.next
            }
          ]
        });
        tour.addStep({
          id: 'fourth-tutorial-second-step',
          text: "<p class='text-center'>With every battle, you also gain <span class='text-success'>Jungle Points</span>, which you need to gather to rank up to the next League. Keep battling until you've reached 12 points, good luck!</p>",
          attachTo: {
            element: '#current-hero-league',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'OK',
              action: function () { hookInstance.pushEvent("tutorial5", {}); this.complete() }
            }
          ]
        });
        break;
      case 6:
        tour.addStep({
          id: 'sixth-tutorial-first-step',
          text: "<p class='text-center'>You're doing great! Looks like you have enough gold to transmute your first Rare item, let's head to the Shop to learn how to do that.</p>",
          buttons: [
            {
              text: 'Open Shop',
              action: function () { hookInstance.pushEventTo("#hero-bar", "toggle-shop", {}); setTimeout(this.next, 500) }
            }
          ],
          cancelIcon: { enabled: true }
        });
        tour.addStep({
          id: 'sixth-tutorial-second-step',
          text: "<p class='text-center'>First, buy another <span class='text-dark'>Normal</span> item, just make sure it's one you don't already have.</p>",
          attachTo: {
            element: '.normal-items',
            on: 'right'
          },
          cancelIcon: { enabled: true }
        });
        break;
      case 7:
        tour.addStep({
          id: 'seventh-tutorial-first-step',
          text: "<p class='text-center'>Now, pick one of the <span class='text-primary'>Rare</span> items and select the 'Transmute' action. We recommend the <span class='text-success'>Tranquil Boots</span>.</p>",
          attachTo: {
            element: '.code-tranquil_boots',
            on: 'left'
          },
          cancelIcon: { enabled: true },
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 20] } }]
          }
        });
        break;
      case 8:
        tour.addStep({
          id: 'eigth-tutorial-first-step',
          text: "<p class='text-center'>Click on your 3 Normal items and press Transmute.</p>",
          attachTo: {
            element: '.inventory-item',
            on: 'left'
          },
          cancelIcon: { enabled: true },
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 20] } }]
          }
        });
        break;
      case 9:
        tour.addStep({
          id: 'ninth-tutorial-first-step',
          text: "<p class='text-center'>Great! You now have your first <span class='text-primary'>Rare item</span>. If you got the Boots, remember to use them when inside a battle.</p><p class='text-center'>Also, make sure to come back here and buy a <span class='text-dark'>Normal item</span> when you have <span class='text-warning'>400 gold</span>  , you can always transmute it into a stronger item later!</p>",
          attachTo: {
            element: '.inventory-item img',
            on: 'left'
          },
          buttons: [
            {
              text: 'OK, back to Ganking',
              action: function () { hookInstance.pushEventTo("#hero-bar", "close-shop", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        break;
      case 11:
        tour.addStep({
          id: 'eleventh-tutorial-first-step',
          text: "<p class='text-center'>You have ranked up to Silver League, congratulations! Now only Gold, Platinum, Diamond and Master Leagues to go ( ͡° ͜ʖ ͡°)</p>",
          attachTo: {
            element: '#current-hero-league',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: tour.next
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        tour.addStep({
          id: 'eleventh-tutorial-second-step',
          text: "<p class='text-center'>After each rank up you get a buff that makes your hero considerably stronger for 3 battles, use this opportunity to battle against <span class='text-danger'>Hard</span> targets!</p>",
          attachTo: {
            element: '#league-buff',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: tour.next
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        tour.addStep({
          id: 'eleventh-tutorial-third-step',
          text: "<p class='text-center'>Keep ganking until you reach the Master League, you're doing realy well! Keeping a high Undefeated Streak will get your more XP and Gold per battle. Also, remember to keep buying items at <span class='text-warning'>the Shop</span> and level up your skills. Have fun!</p>",
          attachTo: {
            element: '#jungle-stats',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Finish Tutorial',
              action: function () { hookInstance.pushEvent("tutorial12", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        break;
      case 13:
        tour.addStep({
          id: 'thirteenth-tutorial-first-step',
          text: "<p class='text-center'>Welcome to the the Arena!</p><p class='text-center'>This is where the true competition happens, as you'll be fighting other players for the #1 spot. Here, there are no draws: you must kill your opponent to win.</p>",
          attachTo: {
            element: '#arena-info',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: tour.next
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          },
          cancelIcon: { enabled: true },
        });
        tour.addStep({
          id: 'thirteenth-tutorial-first-step',
          text: "<p class='text-center'>Instead of XP and Gold, here you fight for Points, which you can also lose from being attacked by other players.</p>",
          attachTo: {
            element: '#current-hero-arena-points',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: tour.next
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          },
        });
        tour.addStep({
          id: 'thirteenth-tutorial-second-step',
          text: "<p class='text-center'>Your Rank is directly tied to how many Points you have. Finish the match ranked in the Top 3 to receive Medals and be ranked among the best of BrowserMOBA.</p>",
          attachTo: {
            element: '#current-hero-rank',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: tour.next
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        tour.addStep({
          id: 'thirteenth-tutorial-third-step',
          text: "<p class='text-center'>If you want to know more about how the Arena works, you can click View Tips at any time. Have fun!</p>",
          attachTo: {
            element: '#main-arena-title',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Finish Tutorial',
              action: function () { hookInstance.pushEvent("tutorial14", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
    }
    return tour;
  }
}

export default Tutorial;