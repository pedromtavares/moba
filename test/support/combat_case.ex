defmodule Test.CombatCase do
  @moduledoc """
  Combat fixtures captured from canonical dev database values on 2026-10-27,
  at rank one, including Roshan's abilities. No seeds, live balancing data, or image files.

  Single turns run without database access. Multi-turn tests use the real turn
  builder and JSON persistence format, with a sandboxed resource version/cache.
  Only proc probabilities are overridden to exercise guaranteed success/failure;
  each scenario also seeds the RNG for random damage ranges.
  """

  alias Moba.Engine.Core.{Processor, Turns}
  alias Moba.Engine.Schema.{Battle, Battler}
  alias Moba.Game.Schema.{Avatar, Hero, Item, Skill}

  @fixture_path Path.expand("../fixtures/engine_resources.json", __DIR__)
  @external_resource @fixture_path
  @catalog @fixture_path |> File.read!() |> Jason.decode!()
  @skills Enum.map(@catalog["skills"], fn attrs ->
            fields =
              for field <- Skill.__schema__(:fields),
                  Map.has_key?(attrs, to_string(field)),
                  into: %{},
                  do: {field, Map.fetch!(attrs, to_string(field))}

            struct!(Skill, fields)
          end)
  @items Enum.map(@catalog["items"], fn attrs ->
           fields =
             for field <- Item.__schema__(:fields),
                 Map.has_key?(attrs, to_string(field)),
                 into: %{},
                 do: {field, Map.fetch!(attrs, to_string(field))}

           struct!(Item, fields)
         end)

  def skills, do: @skills
  def items, do: @items
  def resources, do: @skills ++ @items

  def skill(code, level \\ 1),
    do: Enum.find(@skills, &(&1.code == code && &1.level == level)) || raise("Unknown skill #{code}/#{level}")

  def item(code), do: Enum.find(@items, &(&1.code == code)) || raise("Unknown item #{code}")

  def proc(resource, outcome) do
    if resource.roll_number, do: %{resource | roll_number: if(outcome == :success, do: 101, else: -1)}, else: resource
  end

  def outcomes(resource), do: if(is_nil(resource.roll_number), do: [:success], else: [:success, :failure])

  def seed(label), do: :rand.seed(:exsss, {1, 2, :erlang.phash2(label) + 1})

  def install_catalog do
    season = Moba.Game.current_season()
    uuid = UUID.uuid4()
    season |> Ecto.Changeset.change(resource_uuid: uuid) |> Moba.Repo.update!()
    key = "resources-#{uuid}"
    Cachex.put(:game_cache, key, resources() ++ [Moba.evade()])
    ExUnit.Callbacks.on_exit(fn -> Cachex.del(:game_cache, key) end)
  end

  def battle(left \\ [], right \\ [], left_stats \\ %{}, right_stats \\ %{}) do
    left = hero(101, left, left_stats)
    right = hero(202, right, right_stats)

    %Battle{
      type: "playtest",
      turns: [],
      attacker: left,
      defender: right,
      initiator: left,
      attacker_id: left.id,
      defender_id: right.id,
      initiator_id: left.id,
      attacker_player: nil,
      defender_player: nil,
      initiator_player: nil
    }
  end

  def step(battle, skill \\ nil, item \\ nil, prepare \\ &Function.identity/1) do
    result =
      battle |> Turns.build_turn(%{auto: false, skill: skill, item: item}) |> prepare.() |> Processor.process_turn()

    saved = Turns.serialize(result)
    saved = %{saved | attacker: roundtrip(saved.attacker), defender: roundtrip(saved.defender)}
    {%{battle | turns: battle.turns ++ [saved]}, result}
  end

  def roundtrip(%Battler{} = battler) do
    battler
    |> Ecto.embedded_dump(:json)
    |> Jason.encode!()
    |> Jason.decode!()
    |> then(&Ecto.embedded_load(Battler, &1, :json))
  end

  def chosen(%Skill{passive: false} = skill), do: {skill, nil}
  def chosen(%Item{active: true} = item), do: {nil, item}
  def chosen(_), do: {nil, nil}

  defp hero(id, resources, stats) do
    {skills, items} = Enum.split_with(resources, &match?(%Skill{}, &1))

    hero =
      struct!(
        Hero,
        Map.merge(
          %{
            id: id,
            name: "Hero #{id}",
            total_hp: 10_000,
            total_mp: 400,
            atk: 40,
            power: 0,
            armor: 0,
            speed: 0,
            level: 20,
            pve_tier: 1,
            league_tier: 1,
            avatar_id: id,
            avatar: %Avatar{id: id, code: "test_hero"},
            skills: skills,
            items: items,
            player: nil,
            skill_order: Enum.map(skills, & &1.code),
            item_order: Enum.map(items, & &1.code)
          },
          stats
        )
      )

    Enum.reduce(
      [
        {:item_hp, :base_hp},
        {:item_mp, :base_mp},
        {:item_atk, :base_atk},
        {:item_power, :base_power},
        {:item_armor, :base_armor},
        {:item_speed, :base_speed}
      ],
      hero,
      fn {stat, bonus}, hero ->
        Map.put(hero, stat, Enum.sum(Enum.map(items, &Map.fetch!(&1, bonus))))
      end
    )
  end
end
