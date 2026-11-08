import $ from 'jquery';
import swal from 'sweetalert';
import CombatStage from './combat_stage';
import {initTooltips, hideTooltips} from './tooltips';
import InventoryOrder from './inventory_order';
import LineupOrder from './lineup_order';
import ManualCodex from './manual_codex';
import {InvokeStage} from './invoke_stage';

let Hooks = {};
Hooks.InvokeStage = {...InvokeStage, refreshTooltips: initTooltips, hideTooltips};
Hooks.CombatStage = {...CombatStage, refreshTooltips: initTooltips};
Hooks.InventoryOrder = {...InventoryOrder, hideTooltips};
Hooks.LineupOrder = {...LineupOrder, hideTooltips};
Hooks.ManualCodex = {...ManualCodex, hideTooltips};

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
    const community = el.closest('.community');
    el.addEventListener("click", e => {
      if (community) {
        const loading = "<span class='d-none d-md-inline'>Loading...</span>";
        const loadingText = $(el).find(".loading-text");
        const spinner = loadingText.find(".ui-2x").length
          ? "<i class='ui-icon ui-spinner ui-spin ui-2x'></i><br/>"
          : "<i class='ui-icon ui-spinner ui-spin mr-1'></i>";
        loadingText.html(spinner + loading);
      }
      if (click){
        let payload = {number: val, id: id, type: type, page: page, code: code};
        const heroId = el.getAttribute("phx-value-hero_id");
        if (heroId) payload.hero_id = heroId;
        if (target){
          this.pushEventTo(target, click, payload);
        }else{
          this.pushEvent(click, payload);
        }
        if (community) $(el).prop("disabled", true);
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
      const training = el.closest('[data-training-encounter]');
      const params = {skill_id: skill, item_id: item, hero_id: heroId};
      if (training) this.pushEventTo(training, "next-turn", params);
      else this.pushEvent("next-turn", params);
      e.stopPropagation();
    })
    this.onKeyDown = event => {
      if (event.code !== "Space" || event.defaultPrevented || event.repeat || event.isComposing ||
          event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      if (event.target.closest("input, textarea, select, summary, button, a, [data-toggle='tooltip'], [role='button'], [role='switch'], [contenteditable]:not([contenteditable='false'])")) return;
      if (el.disabled || !el.getClientRects().length) return;

      const dialogOpen = Array.from(document.querySelectorAll("dialog[open], [role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal"))
        .some(element => element.getClientRects().length);
      if (dialogOpen) return;

      event.preventDefault();
      el.click();
    };
    window.addEventListener("keydown", this.onKeyDown);
  },
  destroyed(){
    window.removeEventListener("keydown", this.onKeyDown);
  }
}

Hooks.BattleAutoHotkeys = {
  mounted(){
    this.onAutoKeyDown = event => {
      if (event.defaultPrevented || event.repeat || event.isComposing || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey ||
          event.target.closest("input, textarea, select, [role='textbox'], [contenteditable]:not([contenteditable='false'])")) return;
      const selector = {t: '#training-auto-battle', g: '#training-auto-match'}[event.key.toLowerCase()];
      if (!selector) return;
      const button = this.el.querySelector(selector);
      if (!button || button.disabled || button.getAttribute('aria-disabled') === 'true' || !button.getClientRects().length) return;
      const blocked = Array.from(document.querySelectorAll("dialog[open], [role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal"))
        .some(dialog => dialog.getClientRects().length && !dialog.contains(this.el));
      if (blocked) return;
      event.preventDefault();
      button.click();
    };
    window.addEventListener('keydown', this.onAutoKeyDown);
  },
  destroyed(){ window.removeEventListener('keydown', this.onAutoKeyDown); }
}

Hooks.BattleContinueHotkey = {
  mounted(){
    const interactiveSelector = "input, textarea, select, label, summary, button, a, [phx-click], [data-toggle='tooltip'], [role='button'], [role='switch'], [contenteditable]:not([contenteditable='false'])";
    const continuationSelectors = ["[data-battle-continue=true]", "#league-next-battle", "#load-training", "#load-battles", "#league-battle-over", "#battle-over-duel", "#battle-over-training", "#battle-guest-create"];
    const continuation = root => continuationSelectors
      .map(selector => root.querySelector(selector))
      .find(element => element && !element.disabled && element.getAttribute("aria-disabled") !== "true" && element.getClientRects().length);
    const dialogOpen = () => Array.from(document.querySelectorAll("dialog[open], [role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal"))
      .some(element => element.getClientRects().length);

    this.onResultClick = (event) => {
      if (this.el.dataset.finished !== "true" || event.defaultPrevented || event.button !== 0 ||
          event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;

      const bar = event.target.closest("#battle-bar");
      if (!bar || event.target.closest(interactiveSelector) || dialogOpen()) return;

      continuation(bar)?.click();
    };

    this.onKeyDown = (event) => {
      if (event.code !== "Space" || event.defaultPrevented || event.repeat || event.isComposing ||
          event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      if (this.el.dataset.finished !== "true" || dialogOpen()) return;

      const target = continuation(this.el);
      if (!target) return;

      const interactive = event.target.closest(interactiveSelector);
      if (interactive && interactive !== target) return;
      // Focused buttons already activate natively on Space; links need the shortcut.
      if (interactive === target && target.tagName === "BUTTON") return;

      event.preventDefault();
      target.click();
    };

    this.el.addEventListener("click", this.onResultClick);
    window.addEventListener("keydown", this.onKeyDown);
  },
  destroyed(){
    this.el.removeEventListener("click", this.onResultClick);
    window.removeEventListener("keydown", this.onKeyDown);
  }
}

Hooks.FarmClaimHotkey = {
  mounted(){
    this.onKeyDown = (event) => {
      if (event.code !== "Space" || event.defaultPrevented || event.repeat || event.isComposing ||
          event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;

      if (event.target.closest("input, textarea, select, summary, button, a, [data-toggle='tooltip'], [role='button'], [role='switch'], [contenteditable]:not([contenteditable='false'])")) return;
      if (this.el.disabled || !this.el.getClientRects().length) return;

      const dialogOpen = Array.from(document.querySelectorAll("[role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal"))
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

Hooks.TeamCompletionArrow = {
  mounted(){
    this.link = this.el.closest("a");
    this.dismiss = () => {
      this.el.hidden = true;
      try { localStorage.setItem(this.el.id, "clicked"); } catch {}
    };
    try { this.el.hidden = localStorage.getItem(this.el.id) === "clicked"; } catch {}
    this.link.addEventListener("click", this.dismiss);
  },
  destroyed(){
    this.link.removeEventListener("click", this.dismiss);
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
    this.shopViewportObserver = new ResizeObserver(() => this.updateShopViewport());
    this.shopViewportObserver.observe(this.el);
    this.shopViewportResize = () => requestAnimationFrame(() => this.updateShopViewport());
    window.addEventListener("resize", this.shopViewportResize);
    document.addEventListener("team:hero-switched", this.shopViewportResize);
    this.updateShopViewport();
  },
  updated(){
    this.updateShopViewport();
  },
  updateShopViewport(){
    if (!this.el.closest(".game-page")) return;
    const bar = this.el.getBoundingClientRect();
    if (!bar.height) return;
    this.el.style.setProperty("--shop-hud-height", `${Math.ceil(bar.height)}px`);
    const tabs = this.el.previousElementSibling?.id === "hero-team-tabs" ? this.el.previousElementSibling :
      this.el.closest(".team-training")?.querySelector("#hero-team-tabs");
    if (tabs?.id !== "hero-team-tabs") return;

    const training = this.el.closest(".team-training");
    const content = this.el.closest(".team-hero-panel")?.querySelector(".training-ascent") || training?.querySelector(".training-ascent") || training;
    const progress = this.el.querySelector(".hud-progress .hud-experience");
    const desktop = progress?.getClientRects().length;
    const start = content ? content.getBoundingClientRect().left : bar.left + 15;
    const end = desktop ? progress.getBoundingClientRect().right : content ? content.getBoundingClientRect().right : bar.right - 15;
    tabs.style.left = `${start}px`;
    tabs.style.width = `${Math.max(0, end - start)}px`;
    tabs.style.bottom = `${Math.ceil(window.innerHeight - bar.top - 1)}px`;
    tabs.style.visibility = "visible";
    if (training) {
      training.style.setProperty("--team-hud-space", `${Math.ceil(bar.height + tabs.getBoundingClientRect().height + 6)}px`);
      training.style.setProperty("--team-page-height", `${Math.max(0, window.innerHeight - training.getBoundingClientRect().top - (window.scrollY || 0))}px`);
    }
  },
  destroyed(){
    if (this.shopViewportObserver) this.shopViewportObserver.disconnect();
    if (this.shopViewportResize) {
      window.removeEventListener("resize", this.shopViewportResize);
      document.removeEventListener("team:hero-switched", this.shopViewportResize);
    }
  }
}

Hooks.ShopKeyboard = {
  mounted(){
    this.onShopKeydown = event => {
      if (!this.el.getClientRects().length) return;
      const typing = event.target?.closest("input, textarea, select, [contenteditable]:not([contenteditable='false'])");
      const modified = event.altKey || event.ctrlKey || event.metaKey || event.shiftKey;
      const close = event.key.toLowerCase() === 'f' && !typing && !modified && !event.isComposing && !event.defaultPrevented;
      if (!close) {
        if (!event.defaultPrevented && !typing && !modified && !event.isComposing) this.navigateShop(event);
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      if (event.repeat) return;
      const hero = this.el.getAttribute('phx-value-hero_id');
      const params = hero ? {hero_id: hero} : {};
      if (this.el.getAttribute('phx-target')) this.pushEventTo(this.el, 'close-shop', params);
      else this.pushEvent('close-shop', params);
    };
    document.addEventListener('keydown', this.onShopKeydown, true);
  },
  updated(){
    if (!this.el.getClientRects().length) this.shopCursor = null;
  },
  navigateShop(event){
    const arrows = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'];
    if (!arrows.includes(event.key) && event.code !== 'Space') return;
    const rows = Array.from(this.el.querySelectorAll('.shop-shelf')).map(row =>
      Array.from(row.querySelectorAll('.shop-shelf-label, .shop-tile')).filter(button =>
        button.getClientRects().length && !button.disabled && button.getAttribute('aria-disabled') !== 'true')
    ).filter(row => row.length);
    const buttons = rows.flat();
    if (!buttons.length) return;
    const actions = Array.from(this.el.querySelectorAll('.shop-detail button')).filter(button =>
      button.getClientRects().length && !button.disabled && button.getAttribute('aria-disabled') !== 'true');
    const focused = event.target?.closest('button, a, summary, [role="button"]');
    if (event.code === 'Space' && focused && !buttons.includes(focused) && !actions.includes(focused)) return;
    let current = buttons.includes(focused) ? focused : buttons.find(button => button.id === this.shopCursor);
    current ||= buttons.find(button => button.classList.contains('shop-tile') && button.getAttribute('aria-pressed') === 'true') ||
      buttons.find(button => button.getAttribute('aria-pressed') === 'true') || buttons[0];
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.repeat) return;
    if (event.code === 'Space') {
      if (this.shopInspectionPending) return;
      if (actions.includes(focused)) focused.click();
      else if (this.el.querySelector('.cinematic-shop')?.dataset.recipeRarity && current.getAttribute('phx-click') === 'select-inventory') current.click();
      else {
        const primary = Array.from(this.el.querySelectorAll('.shop-detail .shop-primary, .shop-sell, .transmute-button')).find(button =>
          button.getClientRects().length && !button.disabled && button.getAttribute('aria-disabled') !== 'true');
        primary?.click();
      }
      return;
    }
    if (actions.includes(focused)) {
      const direction = ['ArrowLeft', 'ArrowUp'].includes(event.key) ? -1 : 1;
      const next = event.key === 'ArrowLeft' ? current : actions[(actions.indexOf(focused) + direction + actions.length) % actions.length];
      if (buttons.includes(next)) this.inspectShopButton(next);
      else next.focus({preventScroll: true});
      return;
    }
    const rowIndex = rows.findIndex(row => row.includes(current));
    const row = rows[rowIndex];
    const column = row.indexOf(current);
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      const direction = event.key === 'ArrowLeft' ? -1 : 1;
      if (direction === 1 && column === row.length - 1 && actions.length) {
        this.shopCursor = current.id;
        actions[0].focus({preventScroll: true});
        return;
      }
      current = row[(column + direction + row.length) % row.length];
    } else {
      const direction = event.key === 'ArrowUp' ? -1 : 1;
      const nextRow = rows[(rowIndex + direction + rows.length) % rows.length];
      current = nextRow[Math.min(column, nextRow.length - 1)];
    }
    this.inspectShopButton(current);
  },
  inspectShopButton(button){
    this.shopCursor = button.id;
    button.focus({preventScroll: true});
    const event = button.getAttribute('phx-click');
    // Browsing ingredients must not add them to a transmutation recipe.
    if (event === 'select-inventory' && this.el.querySelector('.cinematic-shop')?.dataset.recipeRarity) return;
    if (!['select-shop', 'select-inventory', 'select-category'].includes(event)) return;
    const params = event === 'select-category' ? {rarity: button.getAttribute('phx-value-rarity')} : {code: button.getAttribute('phx-value-code')};
    const version = this.shopInspectionVersion = (this.shopInspectionVersion || 0) + 1;
    this.shopInspectionPending = true;
    button.dataset.shopInspecting = String(version);
    this.pushEventTo(button.getAttribute('phx-target'), event, params, () => {
      if (button.dataset.shopInspecting === String(version)) delete button.dataset.shopInspecting;
      if (version === this.shopInspectionVersion) this.shopInspectionPending = false;
    });
  },
  destroyed(){
    document.removeEventListener('keydown', this.onShopKeydown, true);
  }
}

Hooks.ToggleShop = {
  mounted(){
    this.el.addEventListener("click", e => {
      const hud = this.el.closest(".hero-bar");
      let modal = $(hud.querySelector(".shop-modal"));
      let toggle = $(hud.querySelectorAll(".toggle-shop"));
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
