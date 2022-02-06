import $ from 'jquery';
import swal from 'sweetalert';
import Tutorial from './tutorial.js';

let Hooks = {};

Hooks.TutorialStep = {
  mounted(){
    const step = $(this.el).data('step');

    Tutorial.start(this, step);
  }
}

Hooks.CompleteTutorial = {
  mounted(){
    this.el.addEventListener("click", e => {
      Tutorial.complete(this)
    });
  }
}

Hooks.Scroll = {
  mounted(){
    this.el.scrollIntoView();
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
    let target = $(el).attr("phx-target-element");
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

Hooks.ToggleChatButton = {
  mounted(){
    this.el.addEventListener("click", e => {
      $("body").toggleClass("right-bar-enabled");
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
    let loading = $(el).attr("loading") || "<span class='d-none d-md-inline'>Loading...</span>"
    el.addEventListener("click", e => {
      $(el).find(".loading-text").html("<i class='fas fa-spinner fa-spin mr-1'></i>"+loading);
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
      $(el).addClass("current-skill");
      $("#active-skill-name").text(name);
      $("#attack-button").attr("data-skill", id);
      e.stopPropagation();
    })
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
        $("#active-item-name").text("");
        $("#attack-button").attr("data-item", "");
      }else{
        $(".item-img").removeClass("current-item");
        $(el).addClass("current-item");
        $("#active-item-name").text("and "+name);
        $("#attack-button").attr("data-item", id);
      }
      e.stopPropagation();
    })
  }
}

Hooks.AttackButton = {
  mounted(){
    let el = this.el;
    el.addEventListener("click", e => {
      let skill = $(el).attr("data-skill") || "";
      let item = $(el).attr("data-item") || "";
      $(el).find(".loading-text").html("<i class='fas fa-spinner fa-spin mr-1'></i> Attacking...");
      $(el).prop("disabled", true);
      this.pushEvent("next-turn", {skill: skill, item: item});
      e.stopPropagation();
    })
  }
}

Hooks.ShareBattle = {
  mounted(){
    let button = $(this.el);
    this.el.addEventListener("click", e => {
      const el = document.createElement('textarea');
      el.value = button.attr('data-link');
      button.text("Battle link copied to clipboard!")
      button.css("margin-right", "-40px");
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
    let el = this.el;
    let turn = $(el).data('turn');
    el.addEventListener("click", e => {
      $("#turn-"+turn).find(".descriptions").addClass("active");
      $(el).closest(".show-all-effects").remove();
    })
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

Hooks.MessageToast = {
  mounted(){
    let el = this.el;
    $(el).toast("show");

    el.addEventListener("click", e => {
      $('.toast').toast("hide");
      $("body").toggleClass("right-bar-enabled");
      this.pushEvent("show-chat", {});
    });
  }
}

Hooks.DuelChallenger = {
  mounted(){
    swal(`You have challenged ${this.el.dataset.other}, waiting for response...`, {
      closeOnClickOutside: false,
      title: "Duel Challenge",
      buttons: {
        confirm: {
          className: "btn btn-danger btn-block challenge-button",
          text: "Close",
        }
      }
    })
  }
}

Hooks.DuelChallenged = {
  mounted(){
    swal(`You are being challenged to a Duel by ${this.el.dataset.other}.`, {
      closeOnClickOutside: false,
      title: "Duel Challenge",
      buttons: {
        confirm: {
          className: "btn btn-danger btn-block challenge-button",
          text: "Accept Challenge",
          value: "start"
        }
      }
    }).then((value) => {
      switch(value){
        case "start":
        this.pushEventTo("#chat", "accept", {});
        break;
      }
    });
  }
}

export default Hooks;
