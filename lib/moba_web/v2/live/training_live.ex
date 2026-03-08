defmodule MobaWeb.V2.TrainingLive do
  use MobaWeb, :v2_live_view

  alias MobaWeb.V2.TutorialComponent

  embed_templates "training_live/*"

  def mount(_, _, socket) do
    with %{assigns: %{current_hero: hero}} = socket = socket_init(socket) do
      if hero && connected?(socket) do
        Game.subscribe_to_hero(hero.id)
        TutorialComponent.subscribe(hero.player_id)
      end

      {:ok, socket}
    end
  end

  def handle_params(_params, _uri, %{assigns: %{current_hero: hero}} = socket) do
    socket = if hero.gold >= 400 && length(hero.items) > 0, do: TutorialComponent.next_step(socket, 6), else: socket

    {:noreply, socket}
  end

  def handle_event("battle", %{"id" => id}, socket) do
    with socket = TutorialComponent.next_step(socket, 2),
         battle = Game.get_target!(id) |> Game.start_pve_battle!() do
      {:noreply, push_navigate(socket, to: ~p"/battles/#{battle.id}")}
    end
  end

  def handle_event("refresh-targets", _, %{assigns: %{current_hero: hero}} = socket) do
    with hero = Game.refresh_targets!(hero),
         targets = Game.list_targets(hero) do
      {:noreply, assign(socket, current_hero: hero, targets: targets)}
    end
  end

  def handle_event("league", _, %{assigns: %{current_hero: hero}} = socket) do
    with socket = TutorialComponent.next_step(socket, 10),
         battle = Game.start_league_battle!(hero) do
      {:noreply, socket |> push_navigate(to: ~p"/battles/#{battle.id}")}
    end
  end

  def handle_event("buyback", _, %{assigns: %{current_hero: hero}} = socket) do
    with hero = Game.buyback!(hero) do
      Game.broadcast_to_hero(hero.id)
      {:noreply, assign(socket, current_hero: hero)}
    end
  end

  def handle_event("shard-buyback", _, %{assigns: %{current_hero: hero}} = socket) do
    with hero = Moba.shard_buyback!(hero) do
      Game.broadcast_to_hero(hero.id)
      {:noreply, assign(socket, current_hero: hero)}
    end
  end

  def handle_event("restart", _, %{assigns: %{current_hero: hero, current_player: player}} = socket) do
    with _ <- Game.archive_hero!(hero),
         skills = Enum.map(hero.skills, &Game.get_skill_by_code!(&1.code, true, 1)) do
      Game.create_current_pve_hero!(%{name: hero.name}, player, hero.avatar, skills)

      {:noreply, socket |> redirect(to: "/training")}
    end
  end

  def handle_event("show-farm-tabs", params, %{assigns: %{current_player: player}} = socket) do
    with show_farm_tabs = not is_nil(Map.get(params, "value")),
         player = Game.update_preferences!(player, %{show_farm_tabs: show_farm_tabs}) do
      {:noreply, assign(socket, current_player: player)}
    end
  end

  def handle_event("show-meditation", _, %{assigns: %{current_hero: hero}} = socket) do
    time_trigger()
    {:noreply, assign(socket, farm_tab: "meditation", farm_rewards: farm_rewards_for(hero, "meditating"))}
  end

  def handle_event("show-mine", _, %{assigns: %{current_hero: hero}} = socket) do
    time_trigger()
    {:noreply, assign(socket, farm_tab: "mine", farm_rewards: farm_rewards_for(hero, "mining"))}
  end

  def handle_event("show-gank", _, socket) do
    {:noreply, assign(socket, farm_tab: "gank")}
  end

  def handle_event("tutorial3", _, socket) do
    {:noreply, socket |> TutorialComponent.next_step(3) |> assign(show_shop: true)}
  end

  def handle_event("tutorial5", _, socket) do
    {:noreply, socket |> TutorialComponent.next_step(5)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, TutorialComponent.finish_training(socket)}
  end

  def handle_event("level", _, %{assigns: %{current_hero: current}} = socket) do
    hero =
      if Application.get_env(:moba, :env) == :dev do
        Game.level_cheat(current)
      else
        current
      end

    Game.broadcast_to_hero(current.id)
    {:noreply, assign(socket, current_hero: hero)}
  end

  def handle_event("skill", %{"code" => code}, %{assigns: %{current_hero: current}} = socket) do
    with hero = Game.level_up_skill!(current, code) do
      Game.broadcast_to_hero(hero.id)
      {:noreply, assign(socket, current_hero: hero)}
    end
  end

  def handle_event("start-edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("finalize-edit", params, %{assigns: %{current_hero: current}} = socket) do
    hero =
      Game.update_hero!(current, %{
        skill_order: params_to_order(params["skill_order"]),
        item_order: params_to_order(params["item_order"])
      })

    {:noreply, assign(socket, editing: false, current_hero: hero)}
  end

  def handle_event("show-build", _, socket) do
    {:noreply, assign(socket, show_build: true)}
  end

  def handle_event("show-navigation", _, socket) do
    {:noreply, assign(socket, show_build: false)}
  end

  def handle_event("close-shop", _, socket) do
    {:noreply, assign(socket, show_shop: false) |> TutorialComponent.next_step(10)}
  end

  def handle_event("toggle-shop", _, socket) do
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_event("select-turns", params, %{assigns: %{current_hero: hero}} = socket) do
    with turns = String.to_integer(params["turns"]),
         selected_turns = if(turns > hero.pve_current_turns, do: hero.pve_current_turns, else: turns) do
      {:noreply, assign(socket, selected_turns: selected_turns)}
    end
  end

  def handle_event(
        "start-farming",
        %{"state" => state},
        %{assigns: %{current_hero: hero, selected_turns: turns}} = socket
      )
      when state in ["meditating", "mining"] do
    with updated_hero = Game.start_farming!(hero, state, turns) do
      time_trigger()
      {:noreply, assign(socket, current_hero: updated_hero)}
    end
  end

  def handle_event("finish-farming", _, %{assigns: %{current_hero: %{id: id, pve_state: state} = hero}} = socket) do
    with %{pve_current_turns: selected_turns} = updated_hero = Game.finish_farming!(hero),
         farm_rewards = farm_rewards_for(updated_hero, state),
         targets = Game.list_targets(updated_hero) do
      Game.broadcast_to_hero(id)

      {:noreply,
       assign(socket,
         current_hero: updated_hero,
         farm_rewards: farm_rewards,
         selected_turns: selected_turns,
         targets: targets
       )}
    end
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    show_shop = if Enum.member?([3, 7, 8, 9], step), do: true, else: socket.assigns.show_shop
    {:noreply, assign(socket, tutorial_step: step, show_shop: show_shop)}
  end

  def handle_info({:shop, :close}, socket) do
    {:noreply, assign(socket, show_shop: false)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, current_hero: Game.get_hero!(id))}
  end

  def handle_info(:current_time, %{assigns: %{current_hero: hero}} = socket) do
    if farming_progression(hero, %{current_time: Timex.now()}) < 100 do
      Process.send_after(self(), :current_time, 1000)
    end

    {:noreply, assign(socket, current_time: Timex.now())}
  end

  def handle_info(:current_time, socket), do: {:noreply, socket}

  defp current_farm_tab(%{pve_state: "meditating"}), do: "meditation"
  defp current_farm_tab(%{pve_state: "mining"}), do: "mine"
  defp current_farm_tab(_), do: "gank"

  defp farm_rewards_for(hero, state),
    do: Enum.filter(hero.pve_farming_rewards, &(&1.state == state)) |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

  defp list_targets(hero) do
    targets = Game.list_targets(hero)
    if length(targets) > 0, do: targets, else: Game.generate_targets!(hero) |> Game.list_targets()
  end

  defp maybe_redirect(%{assigns: %{current_hero: %{finished_at: finished_at} = hero}} = socket)
       when not is_nil(finished_at) do
    redirect(socket, to: ~p"/hero/#{hero.id}")
  end

  defp maybe_redirect(%{assigns: %{current_hero: current_hero}} = socket) when is_nil(current_hero) do
    redirect(socket, to: "/base")
  end

  defp maybe_redirect(socket), do: socket

  defp socket_init(%{assigns: %{current_hero: hero}} = socket) do
    with updated_hero = Game.maybe_finish_pve(hero) do
      socket
      |> assign(current_hero: updated_hero)
      |> maybe_redirect()
      |> training_assigns()
    end
  end

  defp training_assigns(%{assigns: %{current_hero: hero}} = socket) when not is_nil(hero) do
    Cachex.del(:game_cache, hero.player_id)

    with current_time = Timex.now(),
         farm_rewards = farm_rewards_for(hero, "meditating"),
         farm_tab = current_farm_tab(hero),
         pending_battle = Engine.pending_battle(hero.id),
         targets = list_targets(hero) do
      if Enum.member?(["meditation", "mine"], farm_tab), do: time_trigger()

      assign(socket,
        current_hero: hero,
        editing: false,
        current_time: current_time,
        pending_battle: pending_battle,
        farm_rewards: farm_rewards,
        farm_tab: farm_tab,
        show_build: false,
        show_shop: Enum.member?([3, 7, 8, 9], hero.player.tutorial_step),
        selected_turns: hero.pve_current_turns,
        sidebar_code: "training",
        targets: targets,
        tutorial_step: hero.player.tutorial_step
      )
    end
  end

  defp training_assigns(socket), do: socket

  defp time_trigger, do: Process.send_after(self(), :current_time, 100)

  defp boss_available?(%{pve_current_turns: 0, boss_id: boss_id}) when not is_nil(boss_id), do: Game.get_hero!(boss_id)
  defp boss_available?(_), do: false

  defp boss_percentage(boss), do: boss.total_hp * 100 / boss.avatar.total_hp

  defp dead?(%{pve_state: "dead"}), do: true
  defp dead?(_), do: false

  defp difficulty_color(difficulty) do
    case difficulty do
      "weak" -> "success"
      "moderate" -> "primary"
      "strong" -> "danger"
      _ -> "dark"
    end
  end

  defp difficulty_label(difficulty) do
    case difficulty do
      "weak" -> "Easy"
      "moderate" -> "Medium"
      "strong" -> "Hard"
      _ -> "??"
    end
  end

  defp display_farm_tabs?(%{current_hero: %{league_tier: tier}, current_player: player}) do
    tier != Moba.master_league_tier() && player.preferences.show_farm_tabs
  end

  defp display_defense_percentage(target, targets) do
    heroes = Enum.map(targets, & &1.defender)
    with_stats = Enum.map(heroes, &with_display_stats(&1, heroes))
    max = Enum.max_by(with_stats, fn hero -> hero.display_defense end) || target.defender

    if max.display_defense && max.display_defense > 0 do
      max.display_defense && with_display_stats(target.defender, heroes).display_defense * 100 / max.display_defense
    else
      100
    end
  end

  defp display_offense_percentage(target, targets) do
    heroes = Enum.map(targets, & &1.defender)
    with_stats = Enum.map(heroes, &with_display_stats(&1, heroes))
    max = Enum.max_by(with_stats, fn hero -> hero.display_offense end) || target.defender

    if max.display_offense && max.display_offense > 0 do
      with_display_stats(target.defender, heroes).display_offense * 100 / max.display_offense
    else
      100
    end
  end

  defp elapsed_time(%{inserted_at: inserted_at}) do
    Timex.diff(Timex.now(), inserted_at, :minutes)
  end

  defp expert_hero?(%{pve_tier: tier}) when tier >= 4, do: true
  defp expert_hero?(_), do: false

  defp farming_container_background(hero, assigns) do
    if farming_progression(hero, assigns) >= 100 do
      "rgba(54, 64, 74, 0.8)"
    else
      "rgba(54, 64, 74, 0.6)"
    end
  end

  defp farming_progression(%{pve_farming_turns: turns, pve_farming_started_at: started, pve_state: state}, %{
         current_time: current
       })
       when state in ["meditating", "mining"] do
    turn_seconds = turns * Moba.seconds_per_turn()
    total = Timex.shift(started, seconds: turn_seconds)
    total_diff = Timex.diff(total, started, :seconds)
    current_diff = Timex.diff(current, started, :seconds)

    100 * current_diff / total_diff
  end

  defp farming_progression(_, _), do: 100

  defp farming_reward(%{pve_tier: tier}, turns) do
    start..endd = Moba.farm_per_turn(tier)

    "#{start * turns} - #{endd * turns}"
  end

  defp farming_time_left(%{pve_farming_turns: turns, pve_farming_started_at: started}, %{current_time: _}) do
    turn_seconds = turns * Moba.seconds_per_turn()
    Timex.shift(started, seconds: turn_seconds) |> Timex.format("{relative}", :relative) |> elem(1)
  end

  defp max_available_league(%{pve_tier: pve_tier, league_attempts: attempts} = hero) do
    max = Moba.max_available_league(pve_tier)

    if max != Moba.max_league_tier() || attempts == 0 || league_success_rate(hero) >= 100 do
      max
    else
      max - 1
    end
  end

  defp next_league(%{league_tier: current_tier}) do
    cond do
      current_tier + 1 >= Moba.max_league_tier() -> nil
      true -> current_tier + 1
    end
  end

  defp reward_badges_for(%{pve_tier: pve_tier}, difficulty) do
    rewards = Moba.pve_battle_rewards(difficulty, pve_tier)

    "<div class='text-center'><span class='badge badge-pill badge-light-primary mr-1'>+#{rewards} XP</span><span class='badge badge-pill badge-light-warning mr-1'>+#{rewards} Gold</span></div>"
  end

  defp show_league_challenge?(%{pve_current_turns: 0, league_tier: league_tier}) do
    league_tier < Moba.master_league_tier()
  end

  defp show_league_challenge?(_), do: false

  defp turn_percentage(%{pve_current_turns: turns}) do
    (5 - turns) * 100 / 5
  end

  defp with_display_stats(hero, heroes) do
    minimum = minimum_stats(heroes)
    units = Game.avatar_stat_units()

    Map.merge(hero, %{
      display_defense:
        (total_hp(hero) - minimum[:total_hp]) / units[:total_hp] + (total_armor(hero) - minimum[:armor]) / units[:armor],
      display_offense:
        (total_atk(hero) - minimum[:atk]) / units[:atk] + (total_power(hero) - minimum[:power]) / units[:power]
    })
  end

  defp minimum_stats(heroes) do
    %{
      atk: Enum.min_by(heroes, fn hero -> total_atk(hero) end) |> total_atk(),
      total_hp: Enum.min_by(heroes, fn hero -> total_hp(hero) end) |> total_hp(),
      armor: Enum.min_by(heroes, fn hero -> total_armor(hero) end) |> total_armor(),
      power: Enum.min_by(heroes, fn hero -> total_power(hero) end) |> total_power()
    }
  end

  defp total_hp(hero), do: hero.total_hp + hero.item_hp
  defp total_atk(hero), do: hero.atk + hero.item_atk
  defp total_armor(hero), do: hero.armor + hero.item_armor
  defp total_power(hero), do: hero.power + hero.item_power

  defp league_success_rate(%{league_attempts: attempts, league_successes: successes}) when attempts > 0 do
    round(successes * 100 / attempts)
  end

  defp league_success_rate(_), do: 0

  defp hero_bar_stats(assigns) do
    ~H"""
    <div class="btn-group stats-group f-rpg">
      <button
        class="btn btn-icon btn-outline-dark text-danger tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_hp_description(@current_hero)}
      >
        <i class="fa fa-heart mr-1"></i> {@current_hero.total_hp + @current_hero.item_hp}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-info tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_mp_description(@current_hero)}
      >
        <i class="fa fa-bolt"></i> {@current_hero.total_mp + @current_hero.item_mp}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-success tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_atk_description(@current_hero)}
      >
        <i class="fa fa-dagger"></i> {@current_hero.atk + @current_hero.item_atk}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-pink tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_power_description(@current_hero)}
      >
        <i class="fa fa-galaxy"></i> {@current_hero.power + @current_hero.item_power}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-warning tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_armor_description(@current_hero)}
      >
        <i class="fa fa-shield-halved"></i> {@current_hero.armor + @current_hero.item_armor}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-orange tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_speed_description(@current_hero)}
      >
        <i class="fa fa-running"></i> {@current_hero.speed + @current_hero.item_speed}
      </button>
    </div>
    """
  end

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} ->
      code
    end)
  end

  defp edit_orders_label(%{finished_at: finished_at}) when is_nil(finished_at) do
    "Click to edit the skill and item orders that will be preselected so you don't have to manually select them in every battle."
  end

  defp edit_orders_label(_) do
    "Click to edit the skill and item orders that will be used when defending against other players in the Arena."
  end

  defp sorted_items(%{items: items}), do: Game.sort_items(items)

  defp sorted_skills(%{skills: skills}), do: Enum.sort_by(skills, &{&1.ultimate, &1.passive, &1.name})

  defp can_level_skill?(hero, skill), do: Game.can_level_skill?(hero, skill)

  defp max_skill_level(skill), do: Game.max_skill_level(skill)

  defp xp_percentage(hero), do: hero.experience * 100 / xp_to_next_level(hero)

  defp xp_to_next_level(hero), do: Game.xp_to_next_hero_level(hero.level + 1)

  defp next_skill_description(skill) do
    next = Game.get_current_skill!(skill.code, skill.level + 1)

    "#{GH.skill_description(skill)}<hr/>#{GH.skill_description(%{next | name: "Next Level (#{next.level})", level: nil, description: ""})}"
  end

  defp total_hp_description(hero) do
    title = "Health: #{hero.total_hp + hero.item_hp}"
    sub = "Main survival stat. When it reaches 0 in a battle, you die and receive no rewards."

    main =
      "Current base Health: #{hero.total_hp} <br/>Health given by items: #{hero.item_hp}<br/><br/>Health gain on level up: #{hero.avatar.hp_per_level}"

    attribute_description(title, sub, main)
  end

  defp total_mp_description(hero) do
    title = "Energy: #{hero.total_mp + hero.item_mp}"

    sub =
      "Main spending stat, used to power abilities and active items. When it reaches 0 in a battle, you will hit with a Basic Attack, which deals 100% Attack as Normal Damage."

    main =
      "Current base Energy: #{hero.total_mp} <br/>Energy given by items: #{hero.item_mp}<br/><br/>Energy gain on level up: #{hero.avatar.mp_per_level}"

    attribute_description(title, sub, main)
  end

  defp total_atk_description(hero) do
    title = "Attack: #{hero.atk + hero.item_atk}"
    sub = "Base stat used to calculate damage in most skills and items."

    main =
      "Current Attack: #{hero.atk} <br/>Attack given by items: #{hero.item_atk}<br/><br/>Attack gain on level up: #{hero.avatar.atk_per_level}"

    attribute_description(title, sub, main)
  end

  defp total_power_description(hero) do
    title = "Power: #{hero.power + hero.item_power}"

    sub =
      "Amplifies your total damage output and regeneration in a turn by 1% for every point in Power. E.g. 10 Power will give you 10% amplification."

    main = "Current Power: #{hero.power} <br/>Power given by items: #{hero.item_power}"
    attribute_description(title, sub, main)
  end

  defp total_armor_description(hero) do
    title = "Armor: #{hero.armor + hero.item_armor}"

    sub =
      "Reduces the total damage you take on a defending turn, applied after the amplification from the opponent's Power. Each point of Armor will give 1% of damage reduction, with a maximum of 90%."

    main = "Current base Armor: #{hero.armor} <br/>Armor given by items: #{hero.item_armor}"
    attribute_description(title, sub, main)
  end

  defp total_speed_description(hero) do
    title = "Speed: #{hero.speed + hero.item_speed}"

    sub =
      "Each point in Speed gives you 1% chance to initiate a battle. E.g. 50 Speed will give you 50% chance to initiate. When defending, each point in Speed over 100 gives you 1% chance to Evade the next non-ultimate normal damage attack. Evade costs no Energy and has a 2 turn cooldown. E.g. 120 Speed will give you 20% chance to Evade."

    main = "Current base Speed: #{hero.speed} <br/>Speed given by items: #{hero.item_speed}"
    attribute_description(title, sub, main)
  end

  defp attribute_description(title, sub, main) do
    "
      <h3 class='mb-1 text-center'>#{title}</h3>
      <span class='text-dark'>#{sub}</span>
      <div class='text-center mt-1'>
        #{main}
      </div>
    "
  end
end
