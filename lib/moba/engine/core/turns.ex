defmodule Moba.Engine.Core.Turns do
  alias Moba.{Engine, Repo}
  alias Engine.Schema.{Battler, Turn}

  def build_turn(battle, orders) do
    last_turn = List.last(battle.turns)

    {attacker, defender} = prepare_battlers(battle, last_turn, orders)

    %Turn{
      number: ((last_turn && last_turn.number) || 0) + 1,
      attacker: attacker,
      defender: defender,
      battle: battle,
      orders: orders
    }
  end

  def serialize(%{skill: skill, item: item, attacker: attacker, defender: defender} = turn) do
    %{
      turn
      | skill_code: skill && skill.code,
        item_code: item && item.code,
        attacker: serialize_battler(attacker),
        defender: serialize_battler(defender)
    }
  end

  # Heroes in initial pve_tiers are constantly buffed for league battles
  defp buffed_total(%{pve_tier: pve_tier, league_tier: league_tier, bot_difficulty: diff}, %{type: "league"}, total)
       when is_nil(diff) do
    total + round(Moba.league_buff_multiplier(pve_tier, league_tier) * total)
  end

  # Players with an immortal streak will have their heroes nerfed for match battles, aka "Arrogance" debuff
  defp buffed_total(%{player: %{current_immortal_streak: streak}}, %{type: "match"}, total) when streak > 0 do
    total - round(Moba.immortal_streak_multiplier() * streak * total)
  end

  defp buffed_total(_, _, total), do: total

  defp codes_to_resources(codes, pool) do
    Enum.map(codes, fn code ->
      Enum.find(pool, fn resource -> resource.code == code end)
    end)
  end

  # flushes necessary stats for an attacker on a new turn (was a defender last turn)
  defp flush_attacker(battle, %{defender: battler}) do
    hero = hero_from_battler(battle, battler)

    %{
      battler
      | invulnerable: false,
        immortal: false,
        physically_invulnerable: false,
        inneffectable: false,
        turn_armor: battler.turn_armor + battler.next_armor,
        turn_power: battler.turn_power + battler.next_power,
        turn_power_normal: battler.turn_power_normal + battler.next_power_normal,
        turn_power_magic: battler.turn_power_magic + battler.next_power_magic,
        next_armor: 0,
        next_power: 0,
        next_power_normal: 0,
        next_power_magic: 0
    }
    |> flush(hero)
  end

  # flushes necessary stats for a defender on a new turn (was an attacker last turn)
  defp flush_defender(battle, %{attacker: battler}) do
    hero = hero_from_battler(battle, battler)

    %{
      battler
      | turn_armor: 0,
        turn_power: 0,
        turn_power_normal: 0,
        turn_power_magic: 0,
        turn_atk: 0,
        purged_power: 0,
        miss: false,
        silenced: false,
        stunned: false,
        disarmed: false,
        immortal: false
    }
    |> flush(hero)
  end

  defp flush(battler, %{items: items, skills: skills} = hero) do
    %{
      battler
      | damage: 0,
        hp_regen: 0,
        mp_regen: 0,
        mp_burn: 0,
        total_buff: 0,
        total_reduction: 0,
        null_armor: false,
        effects: [],
        active_skills: hero_active_skills(hero),
        passive_skills: hero_passive_skills(hero),
        active_items: hero_active_items(hero),
        passive_items: hero_passive_items(hero),
        skill_order: codes_to_resources(hero.skill_order, [Moba.basic_attack() | skills]),
        item_order: codes_to_resources(hero.item_order, items),
        last_skill: load_resource(battler.last_skill_code, skills),
        double_skill: load_resource(battler.double_skill_code, skills),
        delayed_skill: load_resource(battler.delayed_skill_code, skills),
        permanent_skill: load_resource(battler.permanent_skill_code, skills),
        buffs: load_buffs(battler.buffs),
        debuffs: load_buffs(battler.debuffs),
        defender_buffs: load_buffs(battler.defender_buffs),
        attacker_debuffs: load_buffs(battler.attacker_debuffs)
    }
  end

  defp hero_from_battler(battle, %{player_id: player_id}) when not is_nil(player_id) do
    hero = if battle.attacker_player_id == player_id, do: battle.attacker, else: battle.defender
    preload_hero(hero)
  end

  defp hero_from_battler(battle, %{hero_id: hero_id}) do
    hero = if battle.attacker_id == hero_id, do: battle.attacker, else: battle.defender
    preload_hero(hero)
  end

  defp hero_active_items(%{items: items}), do: Enum.filter(items, & &1.active)
  defp hero_active_skills(%{skills: skills}), do: Enum.filter(skills, &(!&1.passive))
  defp hero_passive_items(%{items: items}), do: Enum.filter(items, & &1.passive)
  defp hero_passive_skills(%{skills: skills}), do: Enum.filter(skills, & &1.passive)

  def keys_to_atoms(string_key_map) when is_map(string_key_map) do
    for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), keys_to_atoms(val)}
  end

  def keys_to_atoms(value), do: value

  defp load_buffs(buffs) do
    Enum.map(buffs, fn buff ->
      buff =
        if Map.get(buff, "duration") do
          keys_to_atoms(buff)
        else
          buff
        end

      level = Map.get(buff, :level, nil)
      Map.put(buff, :resource, load_resource(buff.resource_code, level))
    end)
    |> Enum.reject(&(&1.duration <= 0))
  end

  defp load_resource(code, resources) when is_list(resources) do
    Enum.find(resources, &(&1.code == code))
  end

  defp load_resource(code, level), do: Moba.load_resource(code, level)

  defp prepare_battlers(battle, last_turn, orders) do
    if last_turn do
      {flush_attacker(battle, last_turn), flush_defender(battle, last_turn)}
    else
      {attacker, attacker_player} = {battle.initiator, battle.initiator_player}

      {defender, defender_player} =
        if battle.initiator_player_id == battle.attacker_player_id do
          {battle.defender, battle.defender_player}
        else
          {battle.attacker, battle.attacker_player}
        end

      {prepare_battler(attacker, attacker_player, battle, orders),
       prepare_battler(defender, defender_player, battle, orders)}
    end
  end

  defp preload_hero(hero), do: Repo.preload(hero, [:avatar, :items, :skills])

  # Heroes do not exist in the Engine domain, they must be transformed to a Battler
  defp prepare_battler(hero, player, battle, orders) do
    %{skills: skills, items: items, avatar: avatar} = hero = preload_hero(hero)
    initial_hp = prepare_stat(player, battle, orders, :attacker_initial_hp)
    initial_mp = prepare_stat(player, battle, orders, :attacker_initial_mp)

    %Battler{
      hero_id: hero.id,
      player_id: player && player.id,
      name: hero.name,
      code: avatar.code,
      image: avatar.image,
      is_bot: !is_nil(hero.bot_difficulty),
      level: hero.level,
      total_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      total_mp: buffed_total(hero, battle, hero.total_mp + hero.item_mp),
      current_hp: initial_hp || buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      current_mp: initial_mp || buffed_total(hero, battle, hero.total_mp + hero.item_mp),
      last_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      speed: buffed_total(hero, battle, hero.speed + hero.item_speed),
      atk: buffed_total(hero, battle, hero.atk + hero.item_atk),
      power: buffed_total(hero, battle, hero.power + hero.item_power),
      armor: buffed_total(hero, battle, hero.armor + hero.item_armor),
      base_atk: buffed_total(hero, battle, hero.atk + hero.item_atk),
      base_power: buffed_total(hero, battle, hero.power + hero.item_power),
      base_armor: buffed_total(hero, battle, hero.armor + hero.item_armor),
      active_skills: hero_active_skills(hero),
      passive_skills: hero_passive_skills(hero),
      active_items: hero_active_items(hero),
      passive_items: hero_passive_items(hero),
      skill_order: codes_to_resources(hero.skill_order, [Moba.basic_attack() | skills]),
      item_order: codes_to_resources(hero.item_order, items)
    }
  end

  defp prepare_stat(player, battle, orders, stat) do
    hero_stat = Map.get(orders, stat)
    player_id = player && Map.get(player, :id, nil)

    if player_id && player_id == battle.attacker_player_id && hero_stat do
      hero_stat
    else
      nil
    end
  end

  defp serialize_battler(battler) do
    %{
      battler
      | double_skill_code: serialized_resource(battler, :double_skill),
        delayed_skill_code: serialized_resource(battler, :delayed_skill),
        permanent_skill_code: serialized_resource(battler, :permanent_skill),
        last_skill_code: serialized_resource(battler, :last_skill),
        buffs: serialized_buffs(battler, :buffs),
        debuffs: serialized_buffs(battler, :debuffs),
        defender_buffs: serialized_buffs(battler, :defender_buffs),
        attacker_debuffs: serialized_buffs(battler, :attacker_debuffs)
    }
  end

  defp serialized_buffs(battler, key) do
    buffs = Map.get(battler, key)

    Enum.map(buffs, fn buff ->
      if buff.resource do
        level = Map.get(buff.resource, :level, nil)
        %{buff | resource_code: buff.resource.code, resource: nil, level: level}
      else
        buff
      end
    end)
  end

  defp serialized_resource(battler, key) do
    resource = Map.get(battler, key)
    (resource && resource.code) || nil
  end
end
