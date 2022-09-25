defmodule MobaWeb.BattleView do
  use MobaWeb, :view
  alias MobaWeb.TrainingView

  defdelegate difficulty_color(diff), to: TrainingView
  defdelegate difficulty_label(diff), to: TrainingView

  def active_attacker?(%{attacker: attacker} = battle, last_turn, %{id: player_id}) do
    is_current? = attacker.player_id == player_id

    cond do
      is_current? && is_nil(last_turn) && battle.attacker_id == battle.initiator_id -> true
      is_current? && last_turn && last_turn.attacker.hero_id == battle.defender_id -> true
      true -> false
    end
  end

  def active_attacker?(_, _, _), do: false

  def active_defender?(%{defender: defender} = battle, last_turn, %{id: player_id}) do
    is_current? = defender.player_id == player_id

    cond do
      is_current? && is_nil(last_turn) && battle.defender_id == battle.initiator_id -> true
      is_current? && last_turn && last_turn.attacker.hero_id == battle.attacker_id -> true
      true -> false
    end
  end

  def active_defender?(_, _, _), do: false

  def can_use?(_, %Game.Schema.Item{active: false}), do: false
  def can_use?(_, %Game.Schema.Skill{passive: true}), do: false
  def can_use?(turn, resource), do: Engine.can_use_resource?(turn, resource)

  def preselected_skill(%{double_skill: skill}, _) when not is_nil(skill), do: skill

  def preselected_skill(attacker, turn) do
    attacker.skill_order
    |> Enum.filter(fn skill -> can_use?(turn, skill) end)
    |> Enum.take(1)
    |> List.first()
  end

  def skill_name(%{name: name}), do: name
  def skill_name(skill), do: skill["name"] || "Basic Attack"

  def item_name(nil), do: ""
  def item_name(%{name: name}), do: "and #{name}"
  def item_name(item), do: "and #{item["name"]}"

  def item_activated(%{name: name}), do: name
  def item_activated(item), do: item && item["name"]

  def cooldown_for(nil, _), do: nil
  def cooldown_for(%Game.Schema.Item{active: false}, _), do: nil
  def cooldown_for(%Game.Schema.Skill{passive: true}, _), do: nil

  def cooldown_for(resource, battler) do
    cd = battler.cooldowns[resource.code]
    display_cooldown(cd && cd + 1)
  end

  def effect_descriptions(turn), do: Engine.effect_descriptions(turn)

  def resource_status(resource, battler) do
    cooldown = cooldown_for(resource, battler)

    cond do
      resource.mp_cost && battler.current_mp < resource.mp_cost ->
        icon = content_tag(:i, "", class: "fa fa-bolt")
        content_tag(:span, [icon, " #{resource.mp_cost}"], class: "badge badge-pill badge-primary cooldown")

      cooldown ->
        icon = content_tag(:i, "", class: "fa fa-clock")
        content_tag(:span, [icon, " #{cooldown}"], class: "badge badge-pill badge-warning cooldown")

      true ->
        icon = content_tag(:i, "", class: "fa fa-times")
        content_tag(:span, icon, class: "badge badge-pill badge-danger passive")
    end
  end

  def display_cooldown(result) when result < 0, do: 0
  def display_cooldown(result), do: result

  def render_rewards(%{type: type}, assigns) do
    render("_#{type}_rewards.html", assigns)
  end

  def battle_result(%{type: "pve"} = battle) do
    cond do
      is_nil(battle.winner_id) ->
        "Draw! Both survived."

      battle.winner_id == battle.attacker_id ->
        "Victory! You defeated #{battle.defender.name}."

      battle.winner_id == battle.defender_id ->
        "Defeat! #{battle.defender.name} got the best of you."

      true ->
        ""
    end
  end

  def battle_result(battle) do
    cond do
      battle.winner_id == battle.attacker_id ->
        "Winner: #{battle.attacker.name}"

      true ->
        "Winner: #{battle.defender.name}"
    end
  end

  def battle_result(%{type: "league"} = battle, hero) do
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

  def hero_xp_percentage(%{attacker_snapshot: hero, rewards: rewards}) do
    if hero.leveled_up do
      80
    else
      exp = (hero.experience && hero.experience - rewards.total_xp) || 0
      exp * 100 / xp_to_next_level(hero)
    end
  end

  def battle_xp_percentage(%{attacker_snapshot: hero, rewards: rewards}) do
    if hero.leveled_up do
      20
    else
      rewards.total_xp * 100 / xp_to_next_level(hero)
    end
  end

  defdelegate xp_to_next_level(hero), to: MobaWeb.CurrentHeroView

  def final_points(current_points, rewarded_points) when rewarded_points <= 0 do
    current_points
  end

  def final_points(current_points, rewarded_points) do
    current_points - rewarded_points
  end

  def pvp_points_for(%{rewards: rewards}, true) do
    rewards.attacker_pvp_points
  end

  def pvp_points_for(%{rewards: rewards}, false) do
    rewards.defender_pvp_points
  end

  def current_arena_percentage(_, %{pvp_points: current}) when current == 0, do: 0
  def current_arena_percentage(points, %{pvp_points: current}) when points < 0, do: current * 100 / (current - points)
  def current_arena_percentage(points, %{pvp_points: current}), do: (current - points) * 100 / current

  def victory_arena_percentage(points, %{pvp_points: current}), do: points * 100 / current

  def defeat_arena_percentage(points, _) when points == 0, do: 0
  def defeat_arena_percentage(points, %{pvp_points: current}), do: points * -100 / (current - points)

  def current_league(%{league_tier: tier}) do
    Moba.leagues()[tier]
  end

  def previous_league(%{league_tier: tier}) do
    Moba.leagues()[tier - 1]
  end

  def league_bonus(%{league_tier: tier}) do
    if tier == Moba.max_league_tier() do
      Moba.boss_win_bonus()
    else
      Moba.league_win_bonus()
    end
  end

  def show_step(%{league_tier: tier}, step) do
    step <= Game.max_league_step_for(tier)
  end

  def league_success_rate(%{league_attempts: attempts, league_successes: successes}) when attempts > 0 do
    round(successes * 100 / attempts)
  end

  def league_success_rate(_), do: 0

  def difficulty_badge(%{type: "pve", difficulty: difficulty}) do
    case difficulty do
      "weak" -> content_tag(:div, "EASY", class: "badge badge-light-success")
      "moderate" -> content_tag(:div, "MEDIUM", class: "badge badge-light-primary")
      "strong" -> content_tag(:div, "HARD", class: "badge badge-light-danger")
      _ -> ""
    end
  end

  def difficulty_badge(_), do: ""

  def result_badge(%{type: "pve", winner: winner}, current_hero) do
    cond do
      is_nil(winner) -> content_tag(:span, "TIE", class: "badge badge-light-warning")
      winner.id == current_hero.id -> content_tag(:span, "WIN", class: "badge badge-light-success")
      true -> content_tag(:span, "LOSS", class: "badge badge-light-dark")
    end
  end

  def result_badge(%{winner: winner}, current_hero) do
    cond do
      winner && winner.id == current_hero.id -> content_tag(:span, "WIN", class: "badge badge-light-success")
      true -> content_tag(:span, "LOSS", class: "badge badge-light-danger")
    end
  end

  def reward_badges(%{rewards: rewards} = battle, current_hero) do
    xp =
      if rewards.total_xp > 0 do
        content_tag(:span, "#{rewards.total_xp} XP", class: "badge badge-light-info")
      else
        ""
      end

    gold =
      if rewards.total_gold > 0 do
        content_tag(:span, "#{rewards.total_xp}g", class: "badge badge-light-warning")
      else
        ""
      end

    points =
      if current_hero.id == battle.attacker_id do
        rewards.attacker_pvp_points
      else
        rewards.defender_pvp_points
      end

    pvp =
      if battle.type == "pvp" do
        color = if points > 0, do: "primary", else: "dark"
        content_tag(:span, "#{points} Points", class: "badge badge-light-#{color}")
      else
        ""
      end

    content_tag(:div, [xp, gold, pvp])
  end

  def current_hp(hero) do
    hero.current_hp - hero.hp_regen
  end

  def current_mp(hero) do
    if hero.current_mp + hero.mp_regen > hero.total_mp do
      hero.total_mp
    else
      hero.current_mp - hero.mp_regen
    end
  end

  def hp_result(hero) do
    hero.hp_regen - hero.damage
  end

  def current_hp_percentage(hero) do
    trunc((current_hp(hero) + hero.hp_regen) * 100 / hero.total_hp)
  end

  def hp_result_percentage(hero) do
    result = hp_result(hero) * 100 / hero.total_hp
    display_percentage(result)
  end

  def mp_result(hero) do
    hero.mp_regen + hero_mp_costs(hero) - hero.mp_burn
  end

  def current_mp_percentage(hero) do
    trunc(current_mp(hero) * 100 / hero.total_mp)
  end

  def mp_result_percentage(hero) do
    result = mp_result(hero) * 100 / hero.total_mp
    display_percentage(result)
  end

  def display_percentage(original) when original < 0, do: minimal_percentage(original * -1)
  def display_percentage(original), do: minimal_percentage(original)

  def minimal_percentage(original) when original < 10, do: 10
  def minimal_percentage(original), do: original

  def hp_description(hero) do
    damage = (hero.damage != 0 && "Total #{hero.damage_type} damage: #{hero.damage}. ") || ""
    regen = (hero.hp_regen != 0 && "Health regeneration: #{hero.hp_regen} ") || ""
    "#{damage}#{regen}"
  end

  def mp_description(hero) do
    costs = (hero_mp_costs(hero) != 0 && "Energy costs: #{hero_mp_costs(hero)}. ") || ""
    regen = (hero.mp_regen != 0 && "Energy regeneration: #{hero.mp_regen} ") || ""
    "#{costs}#{regen}"
  end

  def power_description(hero) do
    power = (hero.power != 0 && "Power: #{hero.power}. ") || ""
    buff = (hero.power != 0 && "Total Damage/Regen Buff: #{Kernel.round(hero.total_buff * 100)}% ") || ""
    "#{power}#{buff}"
  end

  def armor_description(hero) do
    armor = (hero.armor != 0 && "Armor: #{hero.armor}. ") || ""
    reduction = (hero.armor != 0 && "Damage Reduction: #{Kernel.round(hero.total_reduction * 100)}% ") || ""
    "#{armor}#{reduction}"
  end

  def atk_description(hero) do
    "Current Attack: #{hero.atk}"
  end

  def turn_skill_description(turn) do
    turn.skill
    |> struct_from_map(as: %Game.Schema.Skill{})
    |> GH.skill_description()
  end

  def turn_item_description(turn) do
    item = struct_from_map(turn.item, as: %Game.Schema.Item{})

    %{item | name: "#{turn.attacker.name} activated #{item.name}"}
    |> GH.item_description()
  end

  def effect_tooltip(code) do
    resource = get_resource(code)

    "
    <h3>#{resource.name}</h3>

    #{resource.description}
    "
  end

  def effect_image(code) do
    code
    |> get_resource()
    |> GH.image_url()
  end

  def hero_mp_costs(hero) do
    Enum.reduce(hero.effects, 0, fn effect, acc ->
      if effect["key"] == "current_mp" || effect["key"] == :current_mp do
        acc + effect["value"]
      else
        acc
      end
    end)
  end

  def last_hero_for(_, turn) when is_nil(turn) do
    nil
  end

  def last_hero_for(hero, turn) do
    if hero.id == turn.attacker.hero_id do
      turn.attacker
    else
      turn.defender
    end
  end

  def link_for(%{id: id, bot_difficulty: diff}, _) when is_nil(diff), do: "/hero/#{id}"
  def link_for(_, %{type: "pvp"}), do: "/arena"
  def link_for(_, _), do: "/training"

  def total_hp_for(hero, nil), do: hero.total_hp + hero.item_hp
  def total_hp_for(_, last_hero), do: last_hero.total_hp

  def total_mp_for(hero, nil), do: hero.total_mp + hero.item_mp
  def total_mp_for(_, last_hero), do: last_hero.total_mp

  def total_atk_for(hero, nil), do: hero.atk + hero.item_atk
  def total_atk_for(_, last_hero), do: last_hero.base_atk

  def total_power_for(hero, nil), do: hero.power + hero.item_power
  def total_power_for(_, last_hero), do: last_hero.base_power

  def total_armor_for(hero, nil), do: hero.armor + hero.item_armor
  def total_armor_for(_, last_hero), do: last_hero.base_armor

  def show_timer?(%{battle: %{duel: %{type: "pvp"}} = battle, last_turn: last_turn, hero: hero}) do
    if last_turn do
      last_turn.attacker.hero_id != hero.id
    else
      battle.initiator_id == hero.id
    end
  end

  def show_timer?(_), do: false

  def win_rate(hero) do
    sum = hero.wins + hero.losses

    if sum > 0 do
      round(hero.wins * 100 / sum)
    else
      0
    end
  end

  defp get_resource(code), do: Moba.load_resource(code) || Moba.basic_attack()
end
