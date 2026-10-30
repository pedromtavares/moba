defmodule Moba.Content.HeroExpansion202610 do
  @moduledoc """
  Manually imports the October 2026 expansion's canonical content.

  Values match the reviewed development database, not seeds. Includes four heroes,
  four ultimates (three ranks each), three normal skills (five ranks each), three
  epic items, and eight Master/Grandmaster skins.

  After deploying the matching engine code and database migrations, run once:

      MIX_ENV=prod mix run --no-start -e 'IO.inspect(Moba.Content.HeroExpansion202610.run())'

  Or, from an assembled release with production database configuration:

      bin/moba eval 'IO.inspect(Moba.Content.HeroExpansion202610.run())'

  Then upload icons/backgrounds through admin and run the existing resource reset
  (`MIX_ENV=prod mix resources`). Import, artwork, and reset belong in the same
  maintenance window: Tavern reads canonical records before the reset publishes
  their playable versions. Regenerate bots afterwards with `MIX_ENV=prod mix bots`
  if they should use the expansion.

  Landing art is separate from admin records. The desktop/mobile images are
  bundled from `assets/static/images/landing/` by the normal asset build and do
  not require manual uploads.

  This is a manual operation, never invoked by deployment or migrations. It writes
  only these canonical records and skins, in one transaction. Existing IDs and art
  are preserved; rerunning reapplies the gameplay values below. Current resource
  versions, player unlocks, existing heroes, and bots are left to the normal reset
  flow. New records have no art until uploaded in admin.
  """

  import Ecto.Query
  alias Moba.Repo
  alias Moba.Game.Schema.{Avatar, Item, Skill, Skin}

  @skills [
    %{
      code: "sunder",
      name: "Sunder",
      effects: "[hp]Health stolen: [base_amount][/hp]",
      cooldown: 6,
      duration: 0,
      ultimate: true,
      description: "Steals Health from the opponent.",
      ranks: [
        %{mp_cost: 20, base_amount: 100},
        %{mp_cost: 30, base_amount: 150},
        %{mp_cost: 40, base_amount: 200}
      ]
    },
    %{
      code: "mana_void",
      name: "Mana Void",
      effects:
        "[damage]Magic damage: [base_damage][/damage]\n[mp]Energy restored: [base_amount][/mp]\n[mp]Enemy Energy drained: up to [base_amount][/mp]",
      cooldown: 5,
      duration: 0,
      ultimate: true,
      description: "Deal magic damage, restore Energy, and drain up to the same amount of Energy from the opponent.",
      ranks: [
        %{mp_cost: 20, base_amount: 20, base_damage: 80},
        %{mp_cost: 30, base_amount: 30, base_damage: 120},
        %{mp_cost: 40, base_amount: 40, base_damage: 160}
      ]
    },
    %{
      code: "pulse_nova",
      name: "Pulse Nova",
      effects: "[damage]Magic damage per pulse: [base_damage][/damage]\n[mp]Energy per pulse: [mp_cost][/mp]",
      cooldown: 0,
      duration: 0,
      ultimate: true,
      description: "Activate to deal magic damage every turn, costing Energy for each pulse.",
      ranks: [
        %{mp_cost: 6, base_damage: 40},
        %{mp_cost: 9, base_damage: 60},
        %{mp_cost: 12, base_damage: 80}
      ]
    },
    %{
      code: "rupture",
      name: "Rupture",
      effects:
        "[damage]Initial magic damage: [base_damage][/damage]\n[damage]Damage reflected: [extra_multiplier]%[/damage]\n[status]Duration: 3 enemy turns[/status]",
      cooldown: 6,
      duration: 3,
      ultimate: true,
      description:
        "Deal magic damage, then reflect a percentage of actual damage received for the next three enemy turns.",
      ranks: [
        %{mp_cost: 20, base_damage: 50, extra_multiplier: 0.4},
        %{mp_cost: 30, base_damage: 75, extra_multiplier: 0.5},
        %{mp_cost: 40, base_damage: 100, extra_multiplier: 0.6}
      ]
    },
    %{
      code: "chakra_magic",
      name: "Chakra Magic",
      effects:
        "[status]Debuffs removed: up to [level], newest first[/status]\n[mp]Energy restored: [base_amount][/mp]\n[status]Cooldown reduction: [extra_amount] turns[/status]",
      mp_cost: 0,
      cooldown: 6,
      duration: 0,
      ultimate: false,
      description: "Remove your newest debuffs, restore Energy, and reduce all running skill and item cooldowns.",
      level_requirement: 1,
      ranks: [
        %{base_amount: 10, extra_amount: 1},
        %{base_amount: 15, extra_amount: 1},
        %{base_amount: 20, extra_amount: 1},
        %{base_amount: 25, extra_amount: 2},
        %{base_amount: 30, extra_amount: 2}
      ]
    },
    %{
      code: "purifying_flames",
      name: "Purifying Flames",
      effects:
        "[damage]Magic damage: [base_damage][/damage]\n[hp]Enemy healing: [base_amount] per turn for 3 turns[/hp]",
      cooldown: 3,
      duration: 3,
      ultimate: false,
      description: "Deal magic damage, then heal the opponent on each of their next three turns.",
      level_requirement: 1,
      ranks: [
        %{mp_cost: 15, base_amount: 20, base_damage: 150},
        %{mp_cost: 23, base_amount: 25, base_damage: 200},
        %{mp_cost: 31, base_amount: 30, base_damage: 250},
        %{mp_cost: 39, base_amount: 35, base_damage: 300},
        %{mp_cost: 47, base_amount: 40, base_damage: 350}
      ]
    },
    %{
      code: "fortunes_end",
      name: "Fortune's End",
      effects: "[damage]Magic damage: [base_damage][/damage]\n[status]Pause enemy buffs: 2 enemy turns[/status]",
      cooldown: 5,
      duration: 2,
      ultimate: false,
      description:
        "Pause the opponent's buffs for 2 of their turns, freezing their effects and remaining durations, then deal magic damage.",
      level_requirement: 1,
      ranks: [
        %{mp_cost: 12, base_damage: 40},
        %{mp_cost: 18, base_damage: 60},
        %{mp_cost: 24, base_damage: 80},
        %{mp_cost: 30, base_damage: 100},
        %{mp_cost: 36, base_damage: 120}
      ]
    }
  ]

  @items [
    %{
      code: "octarine_core",
      name: "Octarine Core",
      active: true,
      rarity: "epic",
      base_hp: 20,
      base_mp: 20,
      effects: "[status]Cooldown reduction: [extra_amount] turns[/status]",
      mp_cost: 15,
      cooldown: 6,
      description: "Reduce all running skill and item cooldowns by 2.",
      extra_amount: 2
    },
    %{
      code: "soul_booster",
      name: "Soul Booster",
      active: true,
      rarity: "epic",
      base_hp: 20,
      base_mp: 40,
      effects: "[mp]Energy restored: [base_amount][/mp]\n[mp]Passive Energy per turn: [extra_amount][/mp]",
      passive: true,
      cooldown: 5,
      base_amount: 25,
      description: "Restore 2 Energy per turn while equipped. Activate to restore Energy.",
      extra_amount: 2
    },
    %{
      code: "bloodstone",
      name: "Bloodstone",
      active: true,
      rarity: "epic",
      base_hp: 45,
      effects: "[hp]Enemy healing stolen: [hp_regen_multiplier]%[/hp]\n[status]Duration: 2 enemy turns[/status]",
      mp_cost: 10,
      cooldown: 6,
      duration: 2,
      base_power: 7,
      description: "Apply a debuff that steals 40% of the opponent's healing for their next two turns.",
      hp_regen_multiplier: 0.4
    }
  ]

  @avatars [
    %{
      atk: 13,
      code: "bloodseeker",
      name: "Bloodseeker",
      role: "bruiser",
      armor: 5,
      power: 12,
      speed: 55,
      total_hp: 275,
      total_mp: 30,
      description: "Bulky bruiser that reflects most damage.",
      hp_per_level: 45,
      mp_per_level: 3,
      atk_per_level: 2,
      ultimate_code: "rupture"
    },
    %{
      atk: 15,
      code: "leshrac",
      name: "Leshrac",
      role: "nuker",
      armor: 0,
      power: 19,
      speed: 20,
      total_hp: 225,
      total_mp: 105,
      description: "Explosive, consistent nuker.",
      hp_per_level: 30,
      mp_per_level: 8,
      atk_per_level: 2,
      ultimate_code: "pulse_nova"
    },
    %{
      atk: 15,
      code: "terrorblade",
      name: "Terrorblade",
      role: "carry",
      armor: 10,
      power: 12,
      speed: 30,
      total_hp: 260,
      total_mp: 40,
      description: "Clean damage and survivability.",
      hp_per_level: 40,
      mp_per_level: 3,
      atk_per_level: 3,
      ultimate_code: "sunder"
    },
    %{
      atk: 25,
      code: "anti_mage",
      name: "Anti-Mage",
      role: "carry",
      armor: 0,
      power: 12,
      speed: 90,
      total_hp: 210,
      total_mp: 20,
      description: "Fast and deadly against casters.",
      hp_per_level: 30,
      mp_per_level: 2,
      atk_per_level: 4,
      ultimate_code: "mana_void"
    }
  ]

  @skins [
    %{code: "stormrage", name: "Stormrage", avatar_code: "terrorblade", league_tier: 5},
    %{code: "inner_abysm", name: "Inner Abysm", avatar_code: "terrorblade", league_tier: 6},
    %{code: "legacy_of_the_awakened", name: "Legacy of the Awakened", avatar_code: "anti_mage", league_tier: 5},
    %{code: "golden_origins", name: "Golden Origins", avatar_code: "anti_mage", league_tier: 6},
    %{code: "spirethorn_regalia", name: "Spirethorn Regalia", avatar_code: "leshrac", league_tier: 5},
    %{code: "eminent_revival", name: "Eminent Revival", avatar_code: "leshrac", league_tier: 6},
    %{code: "primeval_predator", name: "Primeval Predator", avatar_code: "bloodseeker", league_tier: 5},
    %{code: "eztzhoks_chosen", name: "Eztzhok's Chosen", avatar_code: "bloodseeker", league_tier: 6}
  ]

  @doc "Imports canonical content atomically, returning counts of the records applied."
  def run do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    if is_nil(Process.whereis(Repo)) do
      {:ok, _} = Repo.start_link()
    end

    {:ok, counts} =
      Repo.transaction(fn ->
        # Serialize repeated imports, including when no matching rows exist yet.
        Repo.query!("SELECT pg_advisory_xact_lock($1::bigint)", [2_026_102_701])

        skills =
          for definition <- @skills,
              {rank, level} <- Enum.with_index(definition.ranks, 1) do
            attrs =
              definition
              |> Map.delete(:ranks)
              |> Map.merge(rank)
              |> Map.put(:level, level)
              |> Map.put(:damage_type, "magic")
              |> Map.put(:level_requirement, if(definition.ultimate, do: nil, else: 1))
              |> Map.update!(:effects, &String.replace(&1, "[level]", to_string(level)))

            upsert(Skill, attrs)
          end

        Enum.each(@items, &upsert(Item, &1))

        Enum.each(@avatars, fn attrs ->
          ultimate = Enum.find(skills, &(&1.code == attrs.ultimate_code && &1.level == 1))
          upsert(Avatar, Map.merge(attrs, %{ultimate_id: ultimate.id, level_requirement: 1}))
        end)

        Enum.each(@skins, fn attrs ->
          existing = Repo.one(from s in Skin, where: s.code == ^attrs.code)

          if existing && existing.avatar_code != attrs.avatar_code do
            raise "Skin #{attrs.code} already belongs to #{existing.avatar_code}"
          end

          (existing || %Skin{})
          |> Skin.changeset(Map.merge(attrs, %{author_name: "AI", author_link: "https://chat.com"}))
          |> Repo.insert_or_update!()
        end)

        %{avatars: length(@avatars), skill_ranks: length(skills), items: length(@items), skins: length(@skins)}
      end)

    counts
  end

  defp upsert(schema, attrs) do
    query = from r in schema, where: r.code == ^attrs.code and is_nil(r.resource_uuid)
    query = if schema == Skill, do: from(r in query, where: r.level == ^attrs.level), else: query
    existing = Repo.one(query) || struct(schema)

    # Clear obsolete mechanics on older definitions without replacing art or identity.
    defaults =
      schema
      |> struct()
      |> Map.take(schema.__schema__(:fields))
      |> Map.drop([:id, :image, :background, :ultimate_id, :inserted_at, :updated_at])

    attrs = Map.merge(defaults, attrs) |> Map.merge(%{enabled: true, current: false, resource_uuid: nil})
    changeset = schema.changeset(existing, attrs)

    changeset =
      if schema == Avatar,
        do: Ecto.Changeset.put_change(changeset, :ultimate_id, attrs.ultimate_id),
        else: changeset

    Repo.insert_or_update!(changeset)
  end
end
