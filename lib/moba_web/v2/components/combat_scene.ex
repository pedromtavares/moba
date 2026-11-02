defmodule MobaWeb.V2.Components.CombatScene do
  @moduledoc "Presentation data for the combat stage, built exclusively from saved engine turns."

  alias MobaWeb.V2.Components.GameHelpers, as: GH
  alias MobaWeb.V2.Components.TooltipComponents, as: TT
  @generic_effects ~w(stunned silenced disarmed invulnerable physically_invulnerable charging evade)

  def build(battle, initial, next_turn, player) do
    initial = initial || next_turn
    last = List.last(battle.turns) || initial
    resources = resources(next_turn, battle.turns)

    units =
      for {side, hero, owner} <- [
            {"left", battle.attacker, battle.attacker_player_id},
            {"right", battle.defender, battle.defender_player_id}
          ] do
        battler = find_battler(last, hero.id, owner)
        prepared = find_battler(next_turn, hero.id, owner)

        Map.merge(vitals(battler, resources), %{
          side: side,
          id: hero.id,
          name: hero.name,
          avatar: hero.avatar.name,
          art: GH.background_url(hero),
          portrait: GH.image_url(hero.avatar),
          level: battler.level,
          build: build_details(hero, prepared, battle),
          you: not is_nil(owner) && player && player.id == owner
        })
      end

    events =
      battle.turns
      |> Enum.zip([initial | battle.turns])
      |> Enum.map(fn {turn, previous} -> event(battle, turn, previous, resources) end)

    your_turn = player && next_turn.attacker.player_id == player.id

    %{
      id: battle.id,
      context: context(battle.type),
      initiator: Map.get(battle.initiator, :name, ""),
      finished: battle.finished || false,
      winner: winner_side(battle),
      next: side_for(battle, next_turn.attacker),
      status:
        cond do
          battle.finished && is_nil(battle.winner_id) -> "Draw"
          battle.finished -> "#{battle.winner.name} wins"
          your_turn -> "Your turn"
          true -> "Waiting for #{next_turn.attacker.name}"
        end,
      units: units,
      events: events
    }
  end

  defp build_details(hero, prepared, battle) do
    snapshot = battle.loadouts[to_string(hero.id)]

    skills =
      if snapshot,
        do: Enum.map(snapshot["skills"], &Ecto.embedded_load(Moba.Game.Schema.Skill, &1, :json)),
        else: prepared.active_skills ++ prepared.passive_skills

    items =
      if snapshot,
        do: Enum.map(snapshot["items"], &Ecto.embedded_load(Moba.Game.Schema.Item, &1, :json)),
        else: Enum.uniq_by(prepared.active_items ++ prepared.passive_items, & &1.id)

    %{
      tier: hero.league_tier || 0,
      difficulty: Map.get(%{"weak" => "Easy", "moderate" => "Medium", "strong" => "Hard"}, hero.bot_difficulty, ""),
      skills:
        skills
        |> Enum.sort_by(&{&1.ultimate || false, &1.passive || false, &1.name})
        |> Enum.map(&build_resource(&1, :skill)),
      items: Enum.map(items, &build_resource(&1, :item))
    }
  end

  defp build_resource(resource, type) do
    %{
      id: resource.id,
      code: resource.code,
      name: resource.name,
      image: GH.image_url(resource) || "/images/default_skill.png",
      tooltip: if(type == :skill, do: TT.skill_tooltip(resource), else: TT.item_tooltip(resource))
    }
  end

  defp event(battle, turn, previous, resources) do
    actor = side_for(battle, turn.attacker)
    target = if actor == "left", do: "right", else: "left"
    before = states(battle, previous, resources)

    before =
      if turn.number == 1, do: Map.new(before, fn {side, unit} -> {side, %{unit | activeEffects: []}} end), else: before

    after_turn = states(battle, turn, resources)
    loss = max(before[target].hp - after_turn[target].hp, 0)

    critical =
      Enum.any?(turn.attacker.effects, fn effect ->
        effect["resource"] in ["crystalys", "daedalus"] && effect["key"] == "turn_power" &&
          is_number(effect["value"]) && effect["value"] > 0
      end)

    flag =
      cond do
        turn.attacker.stunned -> "Stunned"
        turn.attacker.charging -> "Charging"
        turn.defender.evaded -> "Evaded"
        turn.attacker.miss -> "Miss"
        loss == 0 && (turn.defender.invulnerable || turn.defender.physically_invulnerable) -> "Guarded"
        critical -> "Critical"
        turn.defender.current_hp <= 0 -> "Finishing blow"
        true -> nil
      end

    skill = turn.skill || Moba.basic_attack()
    action = if turn.item, do: "#{skill.name} + #{turn.item.name}", else: skill.name
    descriptions = Moba.Engine.effect_descriptions(turn)

    %{
      number: turn.number,
      actor: actor,
      target: target,
      name: turn.attacker.name,
      skill: if(turn.attacker.stunned, do: "Cannot act", else: action),
      code: skill.code,
      image: GH.image_url(skill),
      damage: max(round(turn.defender.damage || 0), loss),
      tooltip: tooltip(action, Enum.map_join(descriptions, "\n", &elem(&1, 1))),
      kind: if(skill.code == "basic_attack", do: "physical", else: "spell"),
      flag: flag,
      effects: effects(descriptions, skill.code, resources),
      before: before,
      after: after_turn,
      summary:
        cond do
          turn.attacker.stunned -> "#{turn.attacker.name} is stunned · cannot attack"
          flag in ["Evaded", "Miss", "Guarded"] -> "#{turn.attacker.name} used #{action} · #{flag}"
          loss > 0 -> "#{turn.attacker.name} used #{action} · −#{loss} HP"
          true -> "#{turn.attacker.name} used #{action}"
        end
    }
  end

  defp resources(next_turn, turns) do
    battlers = [next_turn.attacker, next_turn.defender]

    pools =
      Enum.flat_map(battlers, fn battler ->
        battler.active_skills ++ battler.passive_skills ++ battler.active_items ++ battler.passive_items
      end)

    ([Moba.basic_attack(), Moba.evade()] ++ pools ++ Enum.flat_map(turns, &[&1.skill, &1.item]))
    |> Enum.reject(&is_nil/1)
    |> Map.new(&{&1.code, &1})
  end

  defp effects(descriptions, skill_code, resources) do
    descriptions
    |> Enum.reject(fn {code, _} -> code == skill_code || code in @generic_effects end)
    |> Enum.map(fn {code, description} ->
      resource = Map.get(resources, code)
      name = if resource, do: resource.name, else: code |> String.replace("_", " ") |> String.capitalize()

      %{
        code: code,
        name: name,
        image: source_image(resource),
        tooltip: tooltip(name, description),
        description: String.replace(description, ~r/\[\/?\w+\]/, "")
      }
    end)
  end

  defp tooltip(name, description) do
    name = name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    description = description |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    "<h3>#{name}</h3>#{TT.formatted_effect_tooltip(description)}"
  end

  defp states(battle, turn, resources) do
    %{
      "left" => vitals(find_battler(turn, battle.attacker_id, battle.attacker_player_id), resources),
      "right" => vitals(find_battler(turn, battle.defender_id, battle.defender_player_id), resources)
    }
  end

  defp find_battler(turn, hero_id, player_id),
    do: Enum.find([turn.attacker, turn.defender], &(&1.hero_id == hero_id && &1.player_id == player_id))

  defp vitals(battler, resources) do
    %{
      hp: max(0, min(round(battler.current_hp), battler.total_hp)),
      maxHp: max(battler.total_hp, 1),
      mp: max(0, min(round(battler.current_mp), battler.total_mp)),
      maxMp: max(battler.total_mp, 0),
      cooldowns: Map.new(battler.cooldowns || %{}, fn {code, remaining} -> {code, max(remaining + 1, 0)} end),
      statuses: %{
        stunned: battler.stunned || false,
        silenced: battler.silenced || false,
        disarmed: battler.disarmed || false
      },
      combatStats: [
        combat_stat("attack", "Attack", battler.atk, battler.base_atk, "Current Attack"),
        combat_stat(
          "power",
          "Power",
          battler.power,
          battler.base_power,
          "Damage/Regen Buff: #{round((battler.total_buff - battler.pierce_buff) * 100)}%"
        ),
        combat_stat(
          "armor",
          "Armor",
          battler.armor,
          battler.base_armor,
          if((battler.armor || 0) < 0,
            do: "Extra Damage Taken: #{round(battler.pierce_buff * 100)}%",
            else: "Damage Reduction: #{round(battler.total_reduction * 100)}%"
          )
        ),
        combat_stat("speed", "Speed", battler.speed, battler.speed, "Initiative")
      ],
      activeEffects: active_effects(battler, resources)
    }
  end

  defp active_effects(battler, resources) do
    flags =
      for field <- [:stunned, :silenced, :disarmed, :invulnerable, :physically_invulnerable, :charging],
          Map.get(battler, field),
          code = status_source(battler, field),
          resource = Map.get(resources, code),
          not is_nil(resource) do
        name = resource.name
        state = field |> Atom.to_string() |> String.replace("_", " ")
        description = "#{battler.name}: #{state} from #{name}."

        %{
          code: resource.code,
          name: name,
          duration: nil,
          kind: "status",
          image: source_image(resource),
          description: description,
          tooltip: tooltip(name, description)
        }
      end

    buffs =
      [{battler.buffs ++ battler.defender_buffs, "buff"}, {battler.debuffs ++ battler.attacker_debuffs, "debuff"}]
      |> Enum.flat_map(fn {buffs, kind} ->
        for buff <- buffs, duration = Map.get(buff, "duration") || Map.get(buff, :duration) || 0, duration > 0 do
          code =
            Map.get(buff, "resource_code") || Map.get(buff, :resource_code) ||
              Map.get(Map.get(buff, :resource) || %{}, :code) || "effect"

          resource = Map.get(resources, code)
          name = if resource, do: resource.name, else: code |> String.replace("_", " ") |> String.capitalize()
          remaining = "#{duration} #{if duration == 1, do: "turn", else: "turns"} remaining."

          description =
            if resource,
              do: "Active on #{battler.name}. #{remaining} #{Map.get(resource, :description) || ""}",
              else: "Active on #{battler.name}. #{remaining}"

          %{
            code: code,
            name: name,
            duration: duration,
            kind: kind,
            image: source_image(resource),
            description: description,
            tooltip: tooltip(name, description)
          }
        end
      end)
      |> Enum.sort_by(& &1.duration, :desc)
      |> Enum.uniq_by(& &1.code)

    Enum.reduce(flags, buffs, fn flag, effects ->
      case Enum.find_index(effects, &(&1.code == flag.code)) do
        nil -> [flag | effects]
        index -> List.update_at(effects, index, &Map.update!(&1, :tooltip, fn text -> text <> flag.tooltip end))
      end
    end)
  end

  defp source_image(%{code: "basic_attack"} = resource), do: GH.image_url(resource)
  defp source_image(%{image: image} = resource) when not is_nil(image), do: GH.image_url(resource)
  defp source_image(_), do: nil

  defp status_source(battler, field) do
    effect =
      Enum.find(Enum.reverse(battler.effects), fn effect ->
        to_string(effect["key"]) == Atom.to_string(field) && effect["value"] not in [nil, false, "false", 0] &&
          effect["resource"] not in @generic_effects
      end)

    cond do
      effect -> effect["resource"]
      field == :charging -> battler.double_skill_code || battler.delayed_skill_code
      true -> nil
    end
  end

  def display_effects(event, active) do
    primary = event && event.code
    triggered = if event, do: event.effects, else: []

    merged =
      Enum.map(triggered, fn effect ->
        case Enum.find(active, &(&1.code == effect.code)) do
          nil ->
            Map.merge(effect, %{duration: nil, kind: "triggered"})

          ongoing ->
            Map.merge(effect, %{
              duration: ongoing.duration,
              kind: ongoing.kind,
              tooltip: effect.tooltip <> ongoing.tooltip
            })
        end
      end)

    merged ++
      Enum.reject(active, fn effect -> effect.code == primary || Enum.any?(triggered, &(&1.code == effect.code)) end)
  end

  defp combat_stat(key, name, value, base, detail) do
    value = round(value || 0)
    base = round(base || 0)
    modifier = value - base

    %{
      key: key,
      name: name,
      value: value,
      modifier: modifier,
      tooltip: "#{name}: #{value}. Base: #{base}. Modifier: #{if modifier > 0, do: "+"}#{modifier}. #{detail}"
    }
  end

  defp side_for(battle, battler) do
    if battler.hero_id == battle.attacker_id && battler.player_id == battle.attacker_player_id,
      do: "left",
      else: "right"
  end

  defp winner_side(%{winner_id: nil}), do: nil

  defp winner_side(%{attacker_id: attacker, defender_id: defender} = battle) when attacker != defender,
    do: if(battle.winner_id == attacker, do: "left", else: "right")

  defp winner_side(battle),
    do:
      if(battle.winner_id == battle.attacker_id && battle.winner_player_id == battle.attacker_player_id,
        do: "left",
        else: "right"
      )

  defp context("league"), do: "League challenge"
  defp context("duel"), do: "Arena · 1v1"
  defp context("match"), do: "Arena · 5v5"
  defp context(_), do: "Training battle"
end
