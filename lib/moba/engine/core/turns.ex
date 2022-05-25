defmodule Moba.Engine.Core.Turns do
  alias Moba.{Game, Engine, Repo}
  alias Engine.Schema.{Battler, Turn}
  alias Engine.Core

  def build_turn(battle, orders) do
    last_turn = List.last(battle.turns)

    {attacker, defender} = prepare_battlers(battle, last_turn)

    %Turn{
      number: ((last_turn && last_turn.number) || 0) + 1,
      attacker: attacker,
      defender: defender,
      battle: battle,
      orders: orders
    }
  end

  # Heroes in initial pve_tiers are constantly buffed for league battles
  defp buffed_total(%{pve_tier: pve_tier, league_tier: league_tier, bot_difficulty: diff}, %{type: "league"}, total)
       when is_nil(diff),
       do: total + round(Moba.league_buff_multiplier(pve_tier, league_tier) * total)

  defp buffed_total(_, _, total), do: total

  defp codes_to_resources(codes, pool) do
    Enum.map(codes, fn code ->
      Enum.find(pool, fn resource -> resource.code == code end)
    end)
  end

  # flushes necessary stats for an attacker on a new turn (was a defender last turn)
  defp flush_attacker(attacker) do
    %{
      attacker
      | invulnerable: false,
        immortal: false,
        physically_invulnerable: false,
        inneffectable: false,
        turn_armor: attacker.turn_armor + attacker.next_armor,
        turn_power: attacker.turn_power + attacker.next_power,
        turn_power_normal: attacker.turn_power_normal + attacker.next_power_normal,
        turn_power_magic: attacker.turn_power_magic + attacker.next_power_magic,
        next_armor: 0,
        next_power: 0,
        next_power_normal: 0,
        next_power_magic: 0,
        double_skill: load_skill(attacker.double_skill),
        delayed_skill: load_skill(attacker.delayed_skill),
        permanent_skill: load_skill(attacker.permanent_skill)
    }
    |> flush()
  end

  # flushes necessary stats for a defender on a new turn (was an attacker last turn)
  defp flush_defender(defender) do
    %{
      defender
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
    |> flush()
  end

  defp flush(battler) do
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
        active_skills: load_skills(battler.active_skills),
        passive_skills: load_skills(battler.passive_skills),
        active_items: load_items(battler.active_items),
        passive_items: load_items(battler.passive_items),
        skill_order: load_skills(battler.skill_order),
        item_order: load_items(battler.item_order),
        last_skill: load_skill(battler.last_skill),
        buffs: load_buffs(battler.buffs),
        debuffs: load_buffs(battler.debuffs),
        defender_buffs: load_buffs(battler.defender_buffs),
        attacker_debuffs: load_buffs(battler.attacker_debuffs)
    }
  end

  def keys_to_atoms(string_key_map) when is_map(string_key_map) do
    for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), keys_to_atoms(val)}
  end

  def keys_to_atoms(value), do: value

  defp load_buffs(buffs) do
    Enum.map(buffs, fn buff ->
      if Map.get(buff, :resource) do
        buff
      else
        resource = Map.get(buff, "resource")
        loaded_resource = if Map.get(resource, "rarity"), do: load_item(resource), else: load_skill(resource)

        buff
        |> keys_to_atoms()
        |> Map.put(:resource, loaded_resource)
      end
    end)
    |> Enum.reject(&(&1.duration <= 0))
  end

  defp load_skill(map), do: load_resource(map, %Game.Schema.Skill{})

  defp load_skills(list), do: Enum.map(list, &load_skill(&1))

  defp load_item(map), do: load_resource(map, %Game.Schema.Item{})

  defp load_items(list), do: Enum.map(list, &load_item(&1))

  defp load_resource(nil, _), do: nil
  defp load_resource(map, struct), do: Moba.struct_from_map(map, as: struct)

  defp prepare_battlers(battle, last_turn) do
    if last_turn do
      {flush_attacker(last_turn.defender), flush_defender(last_turn.attacker)}
    else
      {prepare_battler(battle.initiator, battle), prepare_battler(Core.opponent(battle, battle.initiator_id), battle)}
    end
  end

  # Heroes do not exist in the Engine domain, they must be transformed to a Battler
  defp prepare_battler(hero, battle) do
    %{skills: skills, items: items, avatar: avatar} = hero = Repo.preload(hero, [:avatar, :items, :skills])

    %Battler{
      hero_id: hero.id,
      name: hero.name,
      code: avatar.code,
      image: avatar.image,
      is_bot: !is_nil(hero.bot_difficulty),
      level: hero.level,
      total_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      total_mp: buffed_total(hero, battle, hero.total_mp + hero.item_mp),
      current_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      current_mp: buffed_total(hero, battle, hero.total_mp + hero.item_mp),
      last_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      speed: buffed_total(hero, battle, hero.speed + hero.item_speed),
      atk: buffed_total(hero, battle, hero.atk + hero.item_atk),
      power: buffed_total(hero, battle, hero.power + hero.item_power),
      armor: buffed_total(hero, battle, hero.armor + hero.item_armor),
      base_atk: buffed_total(hero, battle, hero.atk + hero.item_atk),
      base_power: buffed_total(hero, battle, hero.power + hero.item_power),
      base_armor: buffed_total(hero, battle, hero.armor + hero.item_armor),
      active_skills: skills |> Enum.filter(&(!&1.passive)),
      passive_skills: skills |> Enum.filter(& &1.passive),
      active_items: items |> Enum.filter(& &1.active),
      passive_items: items |> Enum.filter(& &1.passive),
      skill_order: codes_to_resources(hero.skill_order, [Moba.basic_attack() | skills]),
      item_order: codes_to_resources(hero.item_order, items)
    }
  end
end
