import $ from 'jquery';
import swal from 'sweetalert';
import Tutorial from './tutorial.js';
import ModernTutorial from './tutorial_modern.js';

let Hooks = {};

Hooks.TutorialStep = {
  mounted(){
    const step = $(this.el).data('step');

    if (this.el.dataset.preview === 'true') {
      ModernTutorial.start(this, step);
    } else {
      Tutorial.start(this, step);
    }
  },
  destroyed(){
    ModernTutorial.stop(this);
  }
}

Hooks.CompleteTutorial = {
  mounted(){
    this.el.addEventListener("click", e => {
      Tutorial.complete(this)
    });
  }
}

Hooks.EqualHeight = {
  mounted(){
    const target = this.el.getAttribute("phx-target")
    const height = $(target).height()
    this.el.style.height = `${height}px`
  },
  updated(){
    const target = this.el.getAttribute("phx-target")
    const height = $(target).height()
    this.el.style.height = `${height}px`
  }
}

Hooks.Scroll = {
  mounted(){
    this.el.scrollIntoView();
  }
}

Hooks.DuelChat = {
  mounted(){
    this.el.scrollTop = this.el.scrollHeight;
    this.handleEvent("duel-message-sent", ({id}) => {
      cancelAnimationFrame(this.chatScrollFrame);
      this.sentMessageId = id;
      this.scrollToSentMessage();
    });
  },
  updated(){
    this.scrollToSentMessage();
  },
  destroyed(){
    cancelAnimationFrame(this.chatScrollFrame);
  },
  scrollToSentMessage(){
    if (!this.sentMessageId || !this.el.querySelector(`#duel-message-${this.sentMessageId}`)) return;
    cancelAnimationFrame(this.chatScrollFrame);
    this.chatScrollFrame = requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight;
      this.sentMessageId = null;
    });
  }
}

Hooks.HalfScroll = {
  mounted(){
    let el = this.el;
    let container = el.getAttribute("phx-container");
    let $container = $(`${container}`);
    let rowpos = $(el).position();
    
    $container.scrollTop(rowpos.top - 300);
  }
}

Hooks.ScrollToTop = {
  mounted(){
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
}

Hooks.AnimateScroll = {
  mounted(){
    let el = this.el;
    let target = el.getAttribute("phx-target-element");
    el.addEventListener("click", e => {
      $('html, body').animate({
          scrollTop: $(`${target}`).offset().top
      }, 200);
    });
  }
}

Hooks.ScrollToTarget = {
  updated(){
    let el = this.el;
    let target = $(el).attr("phx-target-element");
    const targetElement = $(target);
    if (targetElement){
      targetElement[0].scrollIntoView();
    }
  }
}

Hooks.BattleTurnScroll = {
  mounted(){
    this.scrollToTurns();
  },
  updated(){
    this.scrollToTurns();
  },
  destroyed(){
    cancelAnimationFrame(this.scrollFrame);
  },
  scrollToTurns(){
    cancelAnimationFrame(this.scrollFrame);
    this.scrollFrame = requestAnimationFrame(() => {
      const first = document.querySelector(this.el.getAttribute("phx-target-element"));
      const last = document.getElementById(`turn-${this.el.dataset.lastTurn}`);
      if (!first || !last) return;

      const firstPanel = first.querySelector(".combat-turn-panel").getBoundingClientRect();
      const lastPanel = last.querySelector(".combat-turn-panel").getBoundingClientRect();
      const start = Math.min(firstPanel.top, lastPanel.top);
      const end = Math.max(firstPanel.bottom, lastPanel.bottom);
      const bar = document.getElementById("battle-bar");
      const visibleBottom = bar ? Math.min(window.innerHeight, bar.getBoundingClientRect().top) : window.innerHeight;
      const margin = 16;
      // Keep both turns in view when they fit; otherwise prioritize the final response above the HUD.
      const top = end - start <= visibleBottom - margin * 2
        ? window.scrollY + start - margin
        : window.scrollY + end - visibleBottom + margin;
      window.scrollTo({top: Math.max(0, top), behavior: "auto"});
    });
  }
}

Hooks.ToggleDisplay = {
  mounted(){
    let el = this.el;
    let target = $(el).attr("phx-target-element");
    const targetElement = $(target);
    el.addEventListener("mouseover", e => {
      targetElement.addClass("d-block")
    });
    el.addEventListener("mouseout", e => {
      targetElement.removeClass("d-block")
    });
  }
}

Hooks.Loading = {
  mounted(){
    let el = this.el;
    let click = $(el).attr("phx-click");
    let val = $(el).attr("phx-value-number");
    let target = $(el).attr("phx-target");
    let id = $(el).attr("phx-value-id");
    let code = $(el).attr("phx-value-code");
    let type = $(el).attr("phx-value-type");
    let page = $(el).attr("phx-value-page");
    let loading = $(el).attr("loading") || $(el).attr("data-loading") || "<span class='d-none d-md-inline'>Loading...</span>"
    el.addEventListener("click", e => {
      const loadingText = $(el).find(".loading-text");
      
      if (loadingText.find(".ui-2x")[0]){
        loadingText.html("<i class='ui-icon ui-spinner ui-spin ui-2x'></i><br/>"+loading);
      }else{
        loadingText.html("<i class='ui-icon ui-spinner ui-spin mr-1'></i>"+loading);
      }
      
      if (click){
        let payload = {number: val, id: id, type: type, page: page, code: code}
        if (target){
          this.pushEventTo(target, click, payload);
        }else{
          this.pushEvent(click, payload);
        }
        $(el).prop("disabled", true);
        e.stopPropagation();
      }

    })
  }
}

Hooks.InstaSkill = {
  mounted(){
    let el = this.el;
    let click = $(el).attr("phx-click");
    let id = $(el).attr("phx-value-id");
    let name = $(el).attr("data-name");
    el.addEventListener("click", e => {
      $(".skill-img").removeClass("current-skill");
      $(".skill-img[role='button']").attr("aria-pressed", "false");
      $(el).addClass("current-skill");
      if (el.getAttribute("role") === "button") el.setAttribute("aria-pressed", "true");
      $("#active-skill-name").text(name);
      $("#attack-button").attr("data-skill", id);
      e.stopPropagation();
    })
    el.addEventListener("keydown", event => {
      if (el.getAttribute("role") === "button" && (event.key === "Enter" || event.key === " ")) {
        event.preventDefault();
        event.stopPropagation();
        el.click();
      }
    });
  }
}

Hooks.InstaItem = {
  mounted(){
    let el = this.el;
    let click = $(el).attr("phx-click");
    let id = $(el).attr("phx-value-id");
    let name = $(el).attr("data-name");
    el.addEventListener("click", e => {
      if ($(el).hasClass("current-item")){
        $(el).removeClass("current-item");
        if (el.getAttribute("role") === "button") el.setAttribute("aria-pressed", "false");
        $("#active-item-name").text("");
        $("#attack-button").attr("data-item", "");
      }else{
        $(".item-img").removeClass("current-item");
        $(".item-img[role='button']").attr("aria-pressed", "false");
        $(el).addClass("current-item");
        if (el.getAttribute("role") === "button") el.setAttribute("aria-pressed", "true");
        $("#active-item-name").text("and "+name);
        $("#attack-button").attr("data-item", id);
      }
      e.stopPropagation();
    })
    el.addEventListener("keydown", event => {
      if (el.getAttribute("role") === "button" && (event.key === "Enter" || event.key === " ")) {
        event.preventDefault();
        event.stopPropagation();
        el.click();
      }
    });
  }
}

Hooks.AttackButton = {
  mounted(){
    let el = this.el;
    el.addEventListener("click", e => {
      let skill = $(el).attr("data-skill") || "";
      let item = $(el).attr("data-item") || "";
      const heroId = el.dataset.hero;
      $(el).find(".loading-text").html("<i class='ui-icon ui-spinner ui-spin mr-1'></i> Attacking...");
      $(el).prop("disabled", true);
      this.pushEvent("next-turn", {skill_id: skill, item_id: item, hero_id: heroId});
      e.stopPropagation();
    })
  }
}

Hooks.BattleContinueHotkey = {
  mounted(){
    this.onKeyDown = (event) => {
      if (event.key !== "Enter" || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
        return;
      }

      const activeElement = document.activeElement;
      const tagName = activeElement && activeElement.tagName;

      if (
        activeElement &&
          (activeElement.isContentEditable ||
             tagName === "INPUT" ||
             tagName === "TEXTAREA" ||
             tagName === "SELECT" ||
             tagName === "BUTTON")
      ) {
        return;
      }

      const selectors = ["#load-training", "#load-battles", "#league-battle-over", "#battle-over-duel", "#battle-over-training"];

      const target = selectors
        .map((selector) => this.el.querySelector(selector))
        .find((element) => element && !element.disabled);

      if (target) {
        event.preventDefault();
        target.click();
      }
    };

    window.addEventListener("keydown", this.onKeyDown);
  },
  destroyed(){
    window.removeEventListener("keydown", this.onKeyDown);
  }
}

Hooks.FarmClaimHotkey = {
  mounted(){
    this.onKeyDown = (event) => {
      if (event.code !== "Space" || event.defaultPrevented || event.repeat || event.isComposing ||
          event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;

      if (event.target.closest("input, textarea, select, button, a, [role='button'], [role='switch'], [contenteditable]:not([contenteditable='false'])")) return;
      if (this.el.disabled || !this.el.getClientRects().length) return;

      const dialogOpen = Array.from(document.querySelectorAll("[role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal, .shepherd-enabled"))
        .some(element => element.getClientRects().length);
      if (dialogOpen) return;

      event.preventDefault();
      this.el.click();
    };
    window.addEventListener("keydown", this.onKeyDown);
  },
  destroyed(){
    window.removeEventListener("keydown", this.onKeyDown);
  }
}

Hooks.ResetOnSubmit = {
  mounted(){
    this.el.addEventListener("submit", () => {
      const fields = this.el.querySelectorAll("input[type='text'], textarea");

      window.requestAnimationFrame(() => {
        fields.forEach((field) => {
          field.value = "";
        });
      });
    });
  }
}

Hooks.ResetFormOnEvent = {
  mounted(){
    const eventName = this.el.dataset.resetEvent;

    if (!eventName) {
      return;
    }

    this.handleEvent(eventName, () => {
      const fields = this.el.querySelectorAll("input[type='text'], input[type='email'], input[type='password'], textarea");

      fields.forEach((field) => {
        field.value = "";
      });
    });
  }
}

Hooks.ShareBattle = {
  mounted(){
    let button = $(this.el);
    this.el.addEventListener("click", e => {
      const el = document.createElement('textarea');
      el.value = button.attr('data-link');
      button.text(button.attr('data-copy-label') || "Battle link copied to clipboard!");
      if (!button.attr('data-copy-label')) button.css("margin-right", "-40px");
      el.setAttribute('readonly', '');
      el.style.position = 'absolute';
      el.style.left = '-9999px';
      document.body.appendChild(el);
      el.select();
      document.execCommand('copy');
      document.body.removeChild(el);
    });

  }
}

Hooks.ExpandEffects = {
  mounted(){
    const el = this.el;
    el.addEventListener("click", () => {
      if (el.hasAttribute("aria-controls")) {
        const expanded = el.getAttribute("aria-expanded") !== "true";
        document.getElementById(el.getAttribute("aria-controls")).classList.toggle("active", expanded);
        el.setAttribute("aria-expanded", String(expanded));
        el.querySelector(".effect-toggle-label").textContent = expanded ? "Hide details" : "Details";
        el.querySelector("i").className = expanded ? "ui-icon ui-minus" : "ui-icon ui-plus";
      } else {
        $("#turn-" + el.dataset.turn).find(".descriptions").addClass("active");
        $(el).closest(".contracted-effects").remove();
      }
    });
  }
}

Hooks.HeroReviewViewport = {
  mounted(){
    this.resizeReview = () => this.fitReview();
    this.reviewObserver = new ResizeObserver(this.resizeReview);
    const navigation = document.getElementById("topnav");
    if (navigation) this.reviewObserver.observe(navigation);
    window.addEventListener("resize", this.resizeReview);
    this.fitReview();
  },
  updated(){
    this.fitReview();
  },
  destroyed(){
    cancelAnimationFrame(this.reviewFrame);
    this.reviewObserver.disconnect();
    window.removeEventListener("resize", this.resizeReview);
  },
  fitReview(){
    cancelAnimationFrame(this.reviewFrame);
    const hud = document.getElementById("hero-bar");
    if (hud !== this.reviewHud) {
      if (this.reviewHud) this.reviewObserver.unobserve(this.reviewHud);
      this.reviewHud = hud;
      if (hud) this.reviewObserver.observe(hud);
    }
    const hudHeight = hud?.getBoundingClientRect().height || 0;
    const top = this.el.getBoundingClientRect().top + window.scrollY;
    const height = window.innerHeight - top - hudHeight - 24;
    this.el.style.setProperty("--hero-review-hud-height", `${Math.ceil(hudHeight)}px`);
    this.el.style.setProperty("--hero-review-height", `${Math.floor(height)}px`);
    this.el.dataset.viewportFit = String(window.innerWidth > 1100 && height >= 480);
    this.reviewFrame = requestAnimationFrame(() => {
      const overview = this.el.querySelector(".hero-detail-overview");
      if (overview && overview.scrollHeight > overview.clientHeight + 1) {
        this.el.dataset.viewportFit = "false";
      }
    });
  }
}

Hooks.ShopViewport = {
  mounted(){
    if (!this.el.closest(".game-page")) return;
    this.shopViewportObserver = new ResizeObserver(() => {
      this.el.style.setProperty("--shop-hud-height", `${Math.ceil(this.el.getBoundingClientRect().height)}px`);
    });
    this.shopViewportObserver.observe(this.el);
  },
  destroyed(){
    if (this.shopViewportObserver) this.shopViewportObserver.disconnect();
  }
}

Hooks.ToggleShop = {
  mounted(){
    this.el.addEventListener("click", e => {
      let modal = $("#shop-modal");
      let toggle = $(".toggle-shop");
      if (modal.is(":visible")){
        modal.addClass("d-none").removeClass("d-block");
        toggle.removeClass("active-shop");
      }else{
        modal.addClass("d-block").removeClass("d-none");
        toggle.addClass("active-shop")
      }
    })
  }
}

Hooks.DuelChallenger = {
  mounted(){
    swal(`You have challenged ${this.el.dataset.other}, they have 30 seconds to respond...`, {
      closeOnClickOutside: false,
      title: "Duel Challenge",
      buttons: {
        confirm: {
          value: "close",
          className: "btn btn-danger btn-block challenge-button",
          text: "Close",
        }
      },
      timer: 30000
    }).then((value) => {
      switch(value){
        case "close":
          this.pushEventTo("#current-player", "close", {});
          break;
      }
    })
  },
  destroyed() {
    swal.close();
  }
}

Hooks.DuelChallengeDialog = {
  mounted(){
    this.previousFocus = document.activeElement;
    this.dialog = this.el.querySelector('[role="dialog"]');
    this.dialog.focus();
    this.trapFocus = event => {
      const buttons = [...this.dialog.querySelectorAll('button:not(:disabled)')];
      if (event.key === "Escape") {
        event.preventDefault();
        this.el.querySelector('#duel-challenge-close, #duel-challenge-decline')?.click();
      } else if (event.key === "Tab") {
        const first = buttons[0];
        const last = buttons[buttons.length - 1];
        if (event.shiftKey && (document.activeElement === first || document.activeElement === this.dialog)) {
          event.preventDefault();
          last?.focus();
        } else if (!event.shiftKey && (document.activeElement === last || document.activeElement === this.dialog)) {
          event.preventDefault();
          first?.focus();
        }
      }
    };
    document.addEventListener("keydown", this.trapFocus);
  },
  updated(){
    if (!this.dialog.contains(document.activeElement)) this.dialog.focus();
  },
  destroyed(){
    document.removeEventListener("keydown", this.trapFocus);
    if (this.previousFocus?.isConnected) this.previousFocus.focus();
  }
}

Hooks.DuelChallenged = {
  mounted(){
    swal(`You are being challenged to a Duel by ${this.el.dataset.other}.`, {
      closeOnClickOutside: false,
      title: "Duel Challenge",
      buttons: {
        cancel: {
          text: "Reject",
          value: "reject",
          visible: true,
          className: "btn btn-secondary mr-3",
          closeModal: true,
        },
        confirm: {
          className: "btn btn-danger challenge-button",
          text: "Accept",
          value: "accept"
        }
      },
      timer: 30000
    }).then((value) => {
      switch(value){
        case "accept":
          this.pushEventTo("#current-player", "accept", {});
          break;
        case "reject":
          this.pushEventTo("#current-player", "reject", {})
          break;
      }
    });
  }
}

let interval;

Hooks.TurnTimer = {
  mounted(){
    const self = this;
    const el = this.el;
    let autoAttacked = false;
    let offlineCounter = 0;

    interval = setInterval(function () {
      let timer = $(el).attr("data-timer");
      let attack = $("#attack-button");

      if (timer <= 0){
        if (attack[0] && !autoAttacked){
          attack.prop("disabled", true);
          let skill = attack.attr("data-skill") || "";
          let item = attack.attr("data-item") || "";
          let heroId = $(el).attr("data-hero");
          console.log("Turn timer up, auto attacking");
          self.pushEvent("next-turn", {skill_id: skill, item_id: item, hero_id: heroId});
          autoAttacked = true
        }else{
          if (offlineCounter >= 3){
            console.log("Player currently offline, auto attacking.");
            self.pushEvent("check-timer", {});
            offlineCounter = 0;
          }else{
            offlineCounter += 1;
          }
        }
      }else{
        timer = timer - 1;
        attack.prop("disabled", false);
        autoAttacked = false;
      }

      $(el).attr("data-timer", timer); 
      $(el).text(timer);

    }, 1000)    
  },

  destroyed(){
    clearInterval(interval);
  }
}



export default Hooks;
