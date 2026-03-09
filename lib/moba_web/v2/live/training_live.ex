defmodule MobaWeb.V2.TrainingLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.V2.Components.HeroBarComponents

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

  def handle_event("buy", %{"code" => code}, %{assigns: %{current_hero: hero}} = socket) do
    item = cached_item!(code)
    updated_hero = Game.buy_item!(hero, item)
    Game.broadcast_to_hero(updated_hero.id)

    {:noreply, socket |> after_training_shop_update(updated_hero) |> assign(current_hero: updated_hero)}
  end

  def handle_event("sell", %{"code" => code}, %{assigns: %{current_hero: hero}} = socket) do
    item = hero_item_by_code!(hero, code)
    updated_hero = Game.sell_item!(hero, item)
    Game.broadcast_to_hero(updated_hero.id)

    {:noreply, assign(socket, current_hero: updated_hero)}
  end

  def handle_event(
        "finish-transmute",
        %{"transmute_code" => transmute_code, "recipe_codes" => recipe_codes},
        %{assigns: %{current_hero: hero}} = socket
      ) do
    transmute = cached_item!(transmute_code)
    recipe = hero_items_by_codes(hero, recipe_codes)
    updated_hero = Game.transmute_item!(hero, recipe, transmute)
    Game.broadcast_to_hero(updated_hero.id)

    {:noreply, socket |> TutorialComponent.next_step(9) |> assign(current_hero: updated_hero)}
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

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} ->
      code
    end)
  end

  defp after_training_shop_update(%{assigns: %{tutorial_step: 3}} = socket, hero) when length(hero.items) > 1 do
    socket
    |> assign(show_shop: false)
    |> TutorialComponent.next_step(4)
  end

  defp after_training_shop_update(socket, _hero) do
    TutorialComponent.next_step(socket, 7)
  end

  defp cached_item!(code) do
    Enum.find(Moba.cached_items(), &(&1.code == code))
  end

  defp hero_item_by_code!(hero, code) do
    Enum.find(hero.items, &(&1.code == code))
  end

  defp hero_items_by_codes(hero, codes) do
    {items, _remaining} =
      Enum.map_reduce(codes, hero.items, fn code, remaining_items ->
        {item, updated_items} = pop_item_by_code(remaining_items, code)
        {item, updated_items}
      end)

    items
  end

  defp pop_item_by_code(items, code) do
    {matched, rest} = Enum.split_with(items, &(&1.code == code))
    {List.first(matched), Enum.drop(matched, 1) ++ rest}
  end
end
