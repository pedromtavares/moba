defmodule MobaWeb.V2.BattleLive do
  use MobaWeb, :v2_live_view

  alias MobaWeb.V2.TutorialComponent
  alias Moba.Game

  embed_templates "battle_live/*"

  def mount(_, _, %{assigns: %{current_player: player}} = socket) do
    {:ok, assign(socket, tutorial_step: player.tutorial_step)}
  end

  def handle_params(params, _uri, socket) do
    socket = battle_assigns(params, socket)

    if connected?(socket) do
      MobaWeb.subscribe("battle-#{params["id"]}")
    end

    {:noreply, socket}
  end

  def handle_event(
        "next-turn",
        %{"skill_id" => skill_id, "item_id" => item_id, "hero_id" => hero_id},
        %{assigns: %{battle: %{id: battle_id}}} = socket
      ) do
    battle = Engine.get_battle!(battle_id)
    skill = skill_id != "" && Game.get_skill!(skill_id)
    item = item_id != "" && Game.get_item!(item_id)
    last_turn = List.last(battle.turns)
    valid_attacker? = is_nil(last_turn) || last_turn.defender.hero_id == String.to_integer(hero_id)

    if valid_attacker? do
      socket = next_turn(socket, battle, %{skill: skill, item: item}, last_turn)
      {:noreply, check_tutorial(socket, socket.assigns.battle)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("check-timer", _, %{assigns: %{battle: %{id: id}}} = socket) do
    battle = Engine.get_battle!(id)
    last_turn = List.last(battle.turns)
    timer = turn_timer(last_turn, battle)

    if timer < 0 do
      {:noreply, next_turn(socket, battle, %{auto: true}, last_turn)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("next-battle", %{"id" => id}, %{assigns: %{battle: battle}} = socket) do
    latest = Engine.latest_battle(battle.attacker.id)

    if latest.type == "league" && latest.id != String.to_integer(id) do
      {:noreply, push_patch(socket, to: ~p"/battles/#{latest.id}")}
    else
      {:noreply, push_navigate(socket, to: ~p"/training")}
    end
  end

  def handle_event("pick-skill", %{"id" => id}, socket) do
    skill = id != "" && Game.get_skill!(id)
    {:noreply, assign(socket, skill: skill)}
  end

  def handle_info({:turn, %{battle_id: battle_id, turn_number: turn_number}}, socket) do
    battle = Engine.get_battle!(battle_id)
    turn = Engine.build_turn(battle)
    {:noreply, turn_assigns(socket, battle, turn, turn_number)}
  end

  defp battle_assigns(params, socket) do
    battle = Engine.get_battle!(params["id"])
    last_turn = List.last(battle.turns)
    turn = Engine.build_turn(battle)

    socket
    |> assign(
      action_turn_number: nil,
      battle: battle,
      debug: Map.get(params, "debug"),
      hide_sidebar: !battle.finished,
      sidebar_code: "training",
      last_turn: last_turn,
      skill: preselected_skill(turn.attacker, turn),
      snapshot: battle.attacker_snapshot,
      turn: turn,
      turn_timer: turn_timer(last_turn, battle)
    )
    |> check_stuck()
  end

  defp check_stuck(%{assigns: %{last_turn: last_turn, battle: %{type: type} = battle}} = socket)
       when not is_nil(last_turn) and type != "duel" do
    if battle.defender.bot_difficulty && last_turn.defender.hero_id == battle.defender_id do
      next_turn(socket, battle, %{auto: true}, last_turn)
    else
      socket
    end
  end

  defp check_stuck(socket), do: socket

  defp check_tutorial(socket, %{attacker_snapshot: %{league_step: 0}, type: "league"} = battle) do
    if battle.winner_id == battle.attacker_id do
      TutorialComponent.next_step(socket, 11)
    else
      socket
    end
  end

  defp check_tutorial(socket, _), do: socket

  defp next_turn(socket, battle, battle_opts, last_turn) do
    battle = Engine.continue_battle!(battle, battle_opts)
    next_turn = Engine.build_turn(battle)
    turn_number = (last_turn && last_turn.number + 1) || 1

    MobaWeb.broadcast_from(self(), "battle-#{battle.id}", :turn, %{battle_id: battle.id, turn_number: turn_number})
    turn_assigns(socket, battle, next_turn, turn_number)
  end

  defp turn_assigns(socket, battle, turn, turn_number) do
    last_turn = List.last(battle.turns)

    assign(socket,
      action_turn_number: turn_number,
      battle: battle,
      last_turn: last_turn,
      snapshot: battle.attacker_snapshot,
      skill: preselected_skill(turn.attacker, turn),
      turn: turn,
      turn_timer: turn_timer(last_turn, battle)
    )
  end

  defp turn_timer(last_turn, battle) do
    turn_time = (last_turn && last_turn.inserted_at) || battle.inserted_at
    target = Timex.shift(turn_time, seconds: Moba.turn_timer_in_seconds())
    Timex.diff(target, Timex.now(), :seconds)
  end

  defp active_attacker?(battle, last_turn, %{id: player_id}) do
    is_current? = current_attacker?(battle, player_id)

    cond do
      is_current? && is_nil(last_turn) && battle.attacker_id == battle.initiator_id -> true
      is_current? && last_turn && last_turn.attacker.hero_id == battle.defender_id -> true
      true -> false
    end
  end

  defp active_attacker?(_, _, _), do: false

  defp active_defender?(battle, last_turn, %{id: player_id}) do
    is_current? = current_defender?(battle, player_id)

    cond do
      is_current? && is_nil(last_turn) && battle.defender_id == battle.initiator_id -> true
      is_current? && last_turn && last_turn.attacker.hero_id == battle.attacker_id -> true
      true -> false
    end
  end

  defp active_defender?(_, _, _), do: false

  defp can_use?(_, %Game.Schema.Item{active: false}), do: false
  defp can_use?(_, %Game.Schema.Skill{passive: true}), do: false
  defp can_use?(turn, resource), do: Engine.can_use_resource?(turn, resource)

  defp preselected_skill(%{double_skill: skill}, _) when not is_nil(skill), do: skill

  defp preselected_skill(attacker, turn) do
    attacker.skill_order
    |> Enum.filter(fn skill -> can_use?(turn, skill) end)
    |> Enum.take(1)
    |> List.first()
  end

  defp skill_name(%{name: name}), do: name
  defp skill_name(skill), do: (skill && skill["name"]) || "Basic Attack"

  defp item_name(nil), do: ""
  defp item_name(%{name: name}), do: "and #{name}"
  defp item_name(item), do: "and #{item["name"]}"

  defp cooldown_for(nil, _), do: nil
  defp cooldown_for(%Game.Schema.Item{active: false}, _), do: nil
  defp cooldown_for(%Game.Schema.Skill{passive: true}, _), do: nil

  defp cooldown_for(resource, battler) do
    cd = battler.cooldowns[resource.code]
    display_cooldown(cd && cd + 1)
  end

  defp resource_status(resource, battler) do
    cooldown = cooldown_for(resource, battler)

    cond do
      resource.mp_cost && battler.current_mp < resource.mp_cost ->
        raw(
          "<span class='badge badge-pill badge-primary cooldown'><i class='fa fa-bolt'></i> #{resource.mp_cost}</span>"
        )

      cooldown ->
        raw("<span class='badge badge-pill badge-warning cooldown'><i class='fa fa-clock'></i> #{cooldown}</span>")

      true ->
        raw("<span class='badge badge-pill badge-danger passive'><i class='fa fa-times'></i></span>")
    end
  end

  defp display_cooldown(result) when result < 0, do: 0
  defp display_cooldown(result), do: result

  defp battle_result(%{type: "pve"} = battle) do
    cond do
      is_nil(battle.winner_id) -> "Draw! Both survived."
      battle.winner_id == battle.attacker_id -> "Victory! You defeated #{battle.defender.name}."
      battle.winner_id == battle.defender_id -> "Defeat! #{battle.defender.name} got the best of you."
      true -> ""
    end
  end

  defp battle_result(battle) do
    if battle.winner_id == battle.attacker_id,
      do: "Winner: #{battle.attacker.name}",
      else: "Winner: #{battle.defender.name}"
  end

  defp battle_result(%{type: "league"} = battle, hero) do
    winner = battle.winner_id == battle.attacker_id

    cond do
      winner && hero.league_tier == Moba.max_league_tier() ->
        "GGWP! You have beaten the game by ranking up to the Grandmaster League!"

      winner && hero.league_step == 0 ->
        "GG! You have beaten the League Challenge and are now in a higher league!"

      winner ->
        "Victory! Proceed to the next battle of the League Challenge."

      Game.master_league?(hero) ->
        "You have died to Roshan."

      true ->
        "You have died and lost the League Challenge."
    end
  end

  defp hero_xp_percentage(%{attacker_snapshot: hero, rewards: rewards}) do
    if hero.leveled_up,
      do: 80,
      else: ((hero.experience && hero.experience - rewards.total_xp) || 0) * 100 / xp_to_next_level(hero)
  end

  defp battle_xp_percentage(%{attacker_snapshot: hero, rewards: rewards}) do
    if hero.leveled_up, do: 20, else: rewards.total_xp * 100 / xp_to_next_level(hero)
  end

  defp xp_to_next_level(hero), do: Game.xp_to_next_hero_level(hero.level + 1)

  defp current_hp(hero), do: hero.current_hp - hero.hp_regen

  defp current_mp(hero) do
    if hero.current_mp + hero.mp_regen > hero.total_mp, do: hero.total_mp, else: hero.current_mp - hero.mp_regen
  end

  defp hp_result(hero), do: hero.hp_regen - hero.damage
  defp current_hp_percentage(hero), do: trunc((current_hp(hero) + hero.hp_regen) * 100 / hero.total_hp)

  defp hp_result_percentage(hero) do
    hero
    |> hp_result()
    |> Kernel./(hero.total_hp)
    |> Kernel.*(100)
    |> display_percentage()
  end

  defp mp_result(hero), do: hero.mp_regen + hero_mp_costs(hero) - hero.mp_burn
  defp current_mp_percentage(hero), do: trunc(current_mp(hero) * 100 / hero.total_mp)

  defp mp_result_percentage(hero) do
    hero
    |> mp_result()
    |> Kernel./(hero.total_mp)
    |> Kernel.*(100)
    |> display_percentage()
  end

  defp display_percentage(original) when original < 0, do: minimal_percentage(original * -1)
  defp display_percentage(original), do: minimal_percentage(original)
  defp minimal_percentage(original) when original < 10, do: 10
  defp minimal_percentage(original), do: original

  defp hp_description(hero) do
    damage = (hero.damage != 0 && "Total #{hero.damage_type} damage: #{hero.damage}. ") || ""
    regen = (hero.hp_regen != 0 && "Health regeneration: #{hero.hp_regen} ") || ""
    "#{damage}#{regen}"
  end

  defp mp_description(hero) do
    costs = (hero_mp_costs(hero) != 0 && "Energy costs: #{hero_mp_costs(hero)}. ") || ""
    regen = (hero.mp_regen != 0 && "Energy regeneration: #{hero.mp_regen} ") || ""
    "#{costs}#{regen}"
  end

  defp power_description(hero) do
    power = (hero.power != 0 && "Power: #{hero.power}. ") || ""
    total_buff = Kernel.round((hero.total_buff - hero.pierce_buff) * 100)
    buff = (hero.power != 0 && "Total Damage/Regen Buff: #{total_buff}% ") || ""
    "#{power}#{buff}"
  end

  defp armor_description(%{armor: armor} = hero) when armor > 0 do
    armor_s = (hero.armor != 0 && "Armor: #{hero.armor}. ") || ""
    reduction = (hero.armor != 0 && "Damage Reduction: #{Kernel.round(hero.total_reduction * 100)}% ") || ""
    "#{armor_s}#{reduction}"
  end

  defp armor_description(%{armor: armor} = hero) when armor < 0 do
    armor_s = (hero.armor != 0 && "Armor: #{hero.armor}. ") || ""
    buff = (hero.armor != 0 && "Extra Damage Taken: #{Kernel.round(hero.pierce_buff * 100)}% ") || ""
    "#{armor_s}#{buff}"
  end

  defp atk_description(hero), do: "Current Attack: #{hero.atk}"

  defp effect_descriptions(turn), do: Engine.effect_descriptions(turn)

  defp turn_skill_description(turn) do
    turn.skill
    |> struct_from_map(as: %Game.Schema.Skill{})
    |> GH.skill_description()
  end

  defp turn_item_description(turn) do
    item = struct_from_map(turn.item, as: %Game.Schema.Item{})
    %{item | name: "#{turn.attacker.name} activated #{item.name}"} |> GH.item_description()
  end

  defp effect_tooltip(code) do
    resource = get_resource(code)
    "<h3>#{resource.name}</h3>#{resource.description}"
  end

  defp effect_image(code), do: code |> get_resource() |> GH.image_url()

  defp hero_mp_costs(hero) do
    Enum.reduce(hero.effects, 0, fn effect, acc ->
      if effect["key"] == "current_mp" || effect["key"] == :current_mp, do: acc + effect["value"], else: acc
    end)
  end

  defp last_hero_for(_, turn) when is_nil(turn), do: nil
  defp last_hero_for(hero, turn), do: if(hero.id == turn.attacker.hero_id, do: turn.attacker, else: turn.defender)

  defp total_hp_for(hero, nil), do: hero.total_hp + hero.item_hp
  defp total_hp_for(_, last_hero), do: last_hero.total_hp
  defp total_mp_for(hero, nil), do: hero.total_mp + hero.item_mp
  defp total_mp_for(_, last_hero), do: last_hero.total_mp
  defp total_atk_for(hero, nil), do: hero.atk + hero.item_atk
  defp total_atk_for(_, last_hero), do: last_hero.base_atk
  defp total_power_for(hero, nil), do: hero.power + hero.item_power
  defp total_power_for(_, last_hero), do: last_hero.base_power
  defp total_armor_for(hero, nil), do: hero.armor + hero.item_armor
  defp total_armor_for(_, last_hero), do: last_hero.base_armor
  defp total_speed_for(hero, nil), do: hero.speed + hero.item_speed
  defp total_speed_for(_, last_hero), do: last_hero.speed

  defp show_timer?(%{battle: %{duel_id: duel_id} = battle, last_turn: last_turn, hero: hero})
       when not is_nil(duel_id) do
    if last_turn, do: last_turn.attacker.hero_id != hero.id, else: battle.initiator_id == hero.id
  end

  defp show_timer?(_), do: false

  defp skill_hotkey(0), do: "Q"
  defp skill_hotkey(1), do: "W"
  defp skill_hotkey(2), do: "E"
  defp skill_hotkey(3), do: "R"
  defp skill_hotkey(4), do: "F"

  defp item_hotkey(0), do: "1"
  defp item_hotkey(1), do: "2"
  defp item_hotkey(2), do: "3"
  defp item_hotkey(3), do: "4"
  defp item_hotkey(4), do: "5"
  defp item_hotkey(5), do: "6"

  defp show_step(%{league_tier: tier}, step), do: step <= Game.max_league_step_for(tier)

  defp league_bonus(%{league_tier: tier}) do
    if tier == Moba.max_league_tier(), do: Moba.boss_win_bonus(), else: Moba.league_win_bonus()
  end

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

  defp current_attacker?(%{type: "duel", duel: duel, attacker: attacker}, player_id) do
    (attacker.id == duel.player_first_pick_id && duel.player_id == player_id) ||
      (attacker.id == duel.opponent_second_pick_id && duel.opponent_player_id == player_id)
  end

  defp current_attacker?(battle, player_id), do: battle.attacker.player_id == player_id

  defp current_defender?(%{type: "duel", duel: duel, defender: defender}, player_id) do
    (defender.id == duel.player_second_pick_id && duel.player_id == player_id) ||
      (defender.id == duel.opponent_first_pick_id && duel.opponent_player_id == player_id)
  end

  defp current_defender?(battle, player_id), do: battle.defender.player_id == player_id

  defp get_resource(code), do: Moba.load_resource(code) || Moba.basic_attack()
end
