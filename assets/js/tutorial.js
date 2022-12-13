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
          id: 'sixth-two-tutorial-second-step',
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
          text: "<p class='text-center'>Great! You now have your first <span class='text-primary'>Rare item</span>. If you got the Boots, remember to use them during a battle.</p><p class='text-center'>Also, make sure to come back here and buy a <span class='text-dark'>Normal item</span> when you have <span class='text-warning'>400 gold</span>  , you can always transmute it into a stronger item later!</p>",
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
          id: 'eleventh-tutorial-first-step',
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
          text: "<p class='text-center'>This is your Hero collection.<br/><br/> You progress through the game by training with all of the Avatars below to reach the Invoker rank, which the ultimate game objective.<br/><br/> Each Avatar has a specific playstyle and Training gets harder (and more fun!) as you rank up.</p>",
          attachTo: {
            element: '#hero-list-container',
            on: 'top'
          },
          buttons: [
            {
              text: 'Next',
              action: function () { this.next() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        tour.addStep({
          id: 'twenty-second-tutorial-first-step',
          text: "<p class='text-center'>You can Train as many heroes as you want without registering, however if you want to save your Hero collection or play in the PvP Arena, you must create an account. Have fun!</p>",
          attachTo: {
            element: '#create-account-link',
            on: 'right'
          },
          buttons: [
            {
              text: 'Finish Tutorial',
              action: function () { hookInstance.pushEvent("tutorial1", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        break;
      case 30:
        $(".arena")[0] && tour.addStep({
          id: 'thirtieth-tutorial-first-step',
          text: "<p class='text-center'>Welcome to the Arena! Here you get to play with your fully trained Heroes in 5v5 matches against other players in the quest to become The Immortal.</p>",
          attachTo: {
            element: '#pvp-progression',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: function () { this.next() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        $(".arena")[0] && tour.addStep({
          id: 'thirtieth-two-tutorial-first-step',
          text: "<p class='text-center'>Every day you can play up to 30 matches against players in your bracket to compete for a spot in a higher bracket.</p>",
          attachTo: {
            element: '#daily-progression',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: function () { this.next() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        $(".arena")[0] && tour.addStep({
          id: 'thirtieth-three-tutorial-first-step',
          text: "<p class='text-center'>You are currently an Arena Pleb. Win against other Plebs to become a Shadow tomorrow, in order to fight against other Shadows to become an Immortal.</p>",
          attachTo: {
            element: '#current-pvp-tier',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Next',
              action: function () { this.next() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        $(".arena")[0] && tour.addStep({
          id: 'thirtieth-four-tutorial-first-step',
          text: "<p class='text-center'>You can check out more info about the Arena, including how live PvP Duels work, by clicking this button. Now, let's get to the action.</p>",
          attachTo: {
            element: '#arena-info-button',
            on: 'bottom'
          },
          buttons: [
            {
              text: 'Finish Tutorial and Enter Arena',
              action: function () { hookInstance.pushEvent("finish-tutorial", {}); this.complete() }
            }
          ],
          popperOptions: {
            modifiers: [{ name: 'offset', options: { offset: [0, 10] } }]
          }
        });
        break;
      case 31:
        $("#picks-card")[0] && tour.addStep({
          id: 'thirty-first-tutorial-first-step',
          text: "<p class='text-center'>The first part of an Arena match is the picking phase. Here you can build a team of 5 by selecting either from your trained heroes or from a pool of randomized heroes.<br/><br/>You can reorder your selection by Unpicking an already picked hero and picking it again. <br/><br/>When you’re done picking, a button will show up to finally start the match, where your picks will automatically fight the opponents picks until the last hero standing. Good luck!</p>",
          attachTo: {
            element: '#picks-card',
            on: 'left'
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
    }
    return tour;
  }
}

export default Tutorial;
