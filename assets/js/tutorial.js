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
      hookInstance.pushEvent("finish-tutorial", {});
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
        $(".meditation-tab").hide() &&
          $(".mine-tab").hide() && 
          $(".targets")[0] && 
          tour.addStep({
            id: 'first-tutorial-first-step',
            text: "Welcome to Training! Now that you've created your hero, it's time to put it to the test. Battle this target to start your first battle.",
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
          text: "<h3 class='text-center mb-4'>Congrats on your first battle!</h3><p>By Training here you can farm <span class='text-primary'>Experience</span> and <span class='text-warning'>Gold</span> by battling other opponents or by passively farming through Meditation or Mining.</p><p><span class='text-primary'>Experience</span> is used to level up and become stronger, while <span class='text-warning'>Gold</span> is used to buy items in the <span class='text-warning'>Shop</span>, in fact, let's head there now.</p>",
          buttons: [
            {
              text: 'Skip Tutorial',
              secondary: true,
              action: function () { hookInstance.pushEvent("finish-tutorial", {}); this.complete() }
            },
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
          text: "<p class='text-center'>Cool, now you're a bit stronger with those items. You can check all of your stats by mousing over each of them for more detailed information.</p>",
          attachTo: {
            element: '#current-hero-stats',
            on: 'right'
          },
          buttons: [
            {
              text: 'OK, back to battling',
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
              text: 'Skip Tutorial',
              secondary: true,
              action: function () { hookInstance.pushEvent("finish-tutorial", {}); this.complete() }
            },
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
          text: "<p class='text-center'>Click on your 3 Normal items and then click on Transmute.</p>",
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
              text: 'OK, back to Battling',
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
          id: 'tenth-tutorial-first-step',
          text: "<p class='text-center'>You have ranked up to Silver League, congratulations!<br/> Keep farming until you reach at least the Platinum League. Also, remember to keep buying items at <span class='text-warning'>the Shop</span> and to level up your skills on the bottom bar. Have fun!</p>",
          attachTo: {
            element: '#current-training-rank',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Finish Tutorial',
              action: function () { hookInstance.pushEvent("finish-tutorial", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        break;
      case 20:
        tour.addStep({
          id: 'twentieth-tutorial-first-step',
          text: "<p class='text-center'>Welcome to your Base!<br/>This is where you manage all of your Heroes and view your Training progression towards becoming an Invoker. </p>",
          attachTo: {
            element: '#pve-progression',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: function () { hookInstance.pushEvent("tutorial1", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, -60] } }]
          }
        });
        break;
      case 21:
        tour.addStep({
          id: 'twenty-first-tutorial-first-step',
          text: "<p class='text-center'>This is your Hero collection. You progress through the game by training with all of the Avatars below. Each Avatar has a specific playstyle and Training gets harder (and more fun!) as you rank up.<br/><br/>For now, try Training a new Hero (preferably with another Avatar) to be allowed into the Arena, which is where PvP happens. Have fun!</p>",
          attachTo: {
            element: '#hero-list-container',
            on: 'top'
          },
          buttons: [
            {
              text: 'Finish Tutorial',
              action: function () { hookInstance.pushEvent("finish-tutorial", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        break;
      case 30:
        tour.addStep({
          id: 'twentieth-tutorial-first-step',
          text: "<p class='text-center'>Welcome to the Arena! Here you get to play with your fully trained Heroes in 1v1 matches against other players to earn Season Points.<br/><br/>Each match consists of 2 battles with alternating picks, meaning you get to pick first on the first battle and your opponent picks first on the second battle, giving both a chance to outpick each other, so it's important to have a diverse collection of Heroes in order to properly pick against what your opponent throws at you.</p>",
          attachTo: {
            element: '#pvp-progression',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: function () { hookInstance.pushEvent("tutorial1", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, -60] } }]
          }
        });
        break;
      case 31:
        tour.addStep({
          id: 'twentieth-tutorial-first-step',
          text: "<p class='text-center'>There are 2 modes in the Arena: Matchmaking and Duels (PvP).<br/><br/>In Matchmaking you play on your time (similar to Training) against players controlled by the AI. In Duels, however, you play a live match against a real player, so they have to be online to accept your Duel request. Players will appear at the bottom of the page when online.<br/><br/>Duels reward twice as much Season Points as Matchmaking, but do not reward Shards. Make sure you play against all available opponents in Elite Matchmaking to maximize your daily Shard rewards.<br/><br/>If you have any more questions, visit the Game Info page on the sidebar which also has a link to our Discord server where you're welcome to come hang out. Have fun!</p>",
          buttons: [
            {
              text: 'Finish Tutorial',
              action: function () { hookInstance.pushEvent("finish-tutorial", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, -60] } }]
          }
        });
        break;
    }
    return tour;
  }
}

export default Tutorial;
