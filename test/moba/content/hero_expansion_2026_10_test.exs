defmodule Moba.Content.HeroExpansion202610Test do
  use Moba.DataCase

  alias Moba.Content.HeroExpansion202610, as: Import
  alias Moba.Game.Schema.{Avatar, Item, Skill, Skin}

  @avatars ~w(terrorblade anti_mage leshrac bloodseeker)
  @ultimates ~w(sunder mana_void pulse_nova rupture)
  @normals ~w(chakra_magic purifying_flames fortunes_end)
  @items ~w(octarine_core soul_booster bloodstone)
  @skins ~w(stormrage inner_abysm legacy_of_the_awakened golden_origins spirethorn_regalia eminent_revival primeval_predator eztzhoks_chosen)
  @counts %{avatars: 4, skill_ranks: 27, items: 3, skins: 8}

  test "imports the approved balance, rank progression, ultimate links, and Tavern requirements" do
    assert Import.run() == @counts
    assert length(canonical(Skill, @ultimates ++ @normals)) == 27
    assert length(canonical(Item, @items)) == 3
    assert length(canonical(Avatar, @avatars)) == 4
    assert Repo.aggregate(from(s in Skin, where: s.code in @skins), :count) == 8

    expected = [
      {"sunder", :base_amount, [100, 150, 200], [20, 30, 40], 6, 0},
      {"mana_void", :base_damage, [80, 120, 160], [20, 30, 40], 5, 0},
      {"pulse_nova", :base_damage, [40, 60, 80], [6, 9, 12], 0, 0},
      {"rupture", :base_damage, [50, 75, 100], [20, 30, 40], 6, 3},
      {"chakra_magic", :base_amount, [10, 15, 20, 25, 30], [0, 0, 0, 0, 0], 6, 0},
      {"purifying_flames", :base_damage, [150, 200, 250, 300, 350], [15, 23, 31, 39, 47], 3, 3},
      {"fortunes_end", :base_damage, [40, 60, 80, 100, 120], [12, 18, 24, 30, 36], 5, 2}
    ]

    for {code, field, amounts, costs, cooldown, duration} <- expected do
      ranks = canonical(Skill, [code]) |> Enum.sort_by(& &1.level)
      assert Enum.map(ranks, &Map.fetch!(&1, field)) == amounts
      assert Enum.map(ranks, & &1.mp_cost) == costs

      for rank <- ranks do
        assert rank.enabled && !rank.current && !rank.passive
        assert rank.cooldown == cooldown
        assert rank.duration == duration
        assert rank.damage_type == "magic"
        assert rank.ultimate == code in @ultimates
        assert rank.level_requirement == if(rank.ultimate, do: nil, else: 1)
      end
    end

    assert Enum.map(ranks("mana_void"), & &1.base_amount) == [20, 30, 40]
    assert Enum.all?(ranks("mana_void"), &is_nil(&1.other_mp_multiplier))
    assert Enum.map(ranks("rupture"), & &1.extra_multiplier) == [0.4, 0.5, 0.6]
    assert Enum.map(ranks("chakra_magic"), & &1.extra_amount) == [1, 1, 1, 2, 2]
    assert Enum.map(ranks("purifying_flames"), & &1.base_amount) == [20, 25, 30, 35, 40]

    for rank <- ranks("chakra_magic") do
      assert rank.effects =~ "up to #{rank.level}, newest first"
      refute rank.effects =~ "[level]"
    end

    stats = [:total_hp, :total_mp, :atk, :power, :armor, :speed, :hp_per_level, :mp_per_level, :atk_per_level]

    for {code, values} <- [
          {"terrorblade", [260, 40, 15, 12, 10, 30, 40, 3, 3]},
          {"anti_mage", [210, 20, 25, 12, 0, 90, 30, 2, 4]},
          {"leshrac", [225, 105, 15, 19, 0, 20, 30, 8, 2]},
          {"bloodseeker", [275, 30, 13, 12, 5, 55, 45, 3, 2]}
        ] do
      avatar = canon(Avatar, code) |> Repo.preload(:ultimate)
      assert Enum.map(stats, &Map.fetch!(avatar, &1)) == values
      assert avatar.enabled && !avatar.current
      assert avatar.level_requirement == 1
      assert avatar.ultimate.code == avatar.ultimate_code
      assert avatar.ultimate.level == 1
      assert is_nil(avatar.ultimate.resource_uuid)
    end

    bloodstone = canon(Item, "bloodstone")
    assert bloodstone.base_hp == 45 && bloodstone.base_power == 7
    assert bloodstone.hp_regen_multiplier == 0.4
    assert bloodstone.duration == 2 && bloodstone.cooldown == 6 && bloodstone.mp_cost == 10
    refute bloodstone.passive
    soul = canon(Item, "soul_booster")
    assert soul.base_hp == 20 && soul.base_mp == 40
    assert soul.passive && soul.active && soul.extra_amount == 2 && soul.base_amount == 25
    octarine = canon(Item, "octarine_core")
    assert octarine.base_hp == 20 && octarine.base_mp == 20 && octarine.extra_amount == 2
    assert Enum.all?(canonical(Item, @items), &(&1.enabled && &1.active && &1.rarity == "epic"))

    assert MapSet.subset?(MapSet.new(@avatars), MapSet.new(Game.list_unlockable_avatars(), & &1.code))
    assert MapSet.subset?(MapSet.new(@normals), MapSet.new(Game.list_unlockable_skills(), & &1.code))

    for code <- @avatars do
      skins = Repo.all(from s in Skin, where: s.avatar_code == ^code and s.code in @skins)
      assert Enum.sort(Enum.map(skins, & &1.league_tier)) == [5, 6]
      assert Enum.all?(skins, &(&1.author_name == "AI" && &1.author_link == "https://chat.com"))
    end
  end

  test "reruns preserve identities and uploaded art while clearing superseded mechanics" do
    Import.run()
    original_ids = identities()
    image = %{file_name: "admin-icon.png", updated_at: ~N[2026-10-27 12:00:00]}
    background = %{file_name: "admin-background.jpg", updated_at: ~N[2026-10-27 12:00:00]}

    skill = canon(Skill, "mana_void")
    Repo.update!(change(skill, image: image, other_mp_multiplier: 0.25, base_damage: 1))
    item = canon(Item, "bloodstone")
    Repo.update!(change(item, image: image, extra_multiplier: 0.5, passive: true))
    avatar = canon(Avatar, "terrorblade")
    Repo.update!(change(avatar, image: image, background: background, power: 999))
    skin = Repo.get_by!(Skin, code: "stormrage")
    Repo.update!(change(skin, background: background))

    assert Import.run() == @counts
    assert identities() == original_ids
    assert Repo.get!(Skill, skill.id).image == image
    assert Repo.get!(Skill, skill.id).base_damage == 80
    assert is_nil(Repo.get!(Skill, skill.id).other_mp_multiplier)
    assert Repo.get!(Item, item.id).image == image
    refute Repo.get!(Item, item.id).passive
    assert is_nil(Repo.get!(Item, item.id).extra_multiplier)
    assert Repo.get!(Avatar, avatar.id).image == image
    assert Repo.get!(Avatar, avatar.id).background == background
    assert Repo.get!(Avatar, avatar.id).power == 12
    assert Repo.get!(Skin, skin.id).background == background

    after_import = identities()
    Import.run()
    assert identities() == after_import
  end

  test "does not change current versions, unrelated content, or the active season" do
    season = Game.current_season()

    current = [
      Repo.insert!(%Skill{
        code: "mana_void",
        level: 1,
        base_damage: 999,
        current: true,
        resource_uuid: season.resource_uuid
      }),
      Repo.insert!(%Item{code: "bloodstone", base_hp: 999, current: true, resource_uuid: season.resource_uuid})
    ]

    unrelated = Repo.insert!(%Skill{code: "unrelated_import_test", level: 1, base_damage: 42})
    before_import = Enum.map(current ++ [unrelated], &Repo.reload!/1)
    Import.run()

    for row <- before_import, do: assert(Repo.get!(row.__struct__, row.id) == row)
    assert Game.current_season() == season
  end

  test "a conflicting skin aborts the entire import" do
    # The collision happens after skills/items/avatars were processed.
    Import.run()
    skill = canon(Skill, "mana_void") |> change(base_damage: 7) |> Repo.update!()
    skin = Repo.get_by!(Skin, code: "eztzhoks_chosen")
    Repo.update!(change(skin, avatar_code: "axe"))

    assert_raise RuntimeError, "Skin eztzhoks_chosen already belongs to axe", fn -> Import.run() end
    assert Repo.get!(Skill, skill.id).base_damage == 7
    assert Repo.get!(Skin, skin.id).avatar_code == "axe"
  end

  test "the normal resource reset publishes playable versions and keeps Tavern gating" do
    Import.run()
    previous_uuid = Game.current_season().resource_uuid
    Moba.Conductor.regenerate_resources!()
    uuid = Game.current_season().resource_uuid
    refute uuid == previous_uuid

    for schema <- [Skill, Item, Avatar] do
      codes =
        case schema do
          Skill -> @ultimates ++ @normals
          Item -> @items
          Avatar -> @avatars
        end

      for source <- canonical(schema, codes) do
        query = from r in schema, where: r.code == ^source.code and r.current and r.resource_uuid == ^uuid
        query = if schema == Skill, do: from(r in query, where: r.level == ^source.level), else: query
        published = Repo.one!(query)
        refute published.id == source.id

        fields = schema.__schema__(:fields) -- [:id, :inserted_at, :updated_at, :current, :resource_uuid, :ultimate_id]
        assert Map.take(published, fields) == Map.take(source, fields)

        if schema == Avatar do
          ultimate = Repo.get!(Skill, published.ultimate_id)
          assert ultimate.code == published.ultimate_code && ultimate.level == 1
          assert ultimate.current && ultimate.resource_uuid == uuid
        end
      end
    end

    refute Enum.any?(Game.list_creation_avatars([]), &(&1.code in @avatars))
    refute Enum.any?(Game.list_creation_skills(1), &(&1.code in @normals))
    assert Enum.any?(Game.list_creation_avatars(["anti_mage"]), &(&1.code == "anti_mage"))
    assert Enum.any?(Game.list_creation_skills(1, ["chakra_magic"]), &(&1.code == "chakra_magic"))
  end

  defp canonical(schema, codes) do
    Repo.all(from r in schema, where: r.code in ^codes and is_nil(r.resource_uuid))
  end

  defp canon(schema, code), do: canonical(schema, [code]) |> Enum.sort_by(& &1.id) |> hd()
  defp ranks(code), do: canonical(Skill, [code]) |> Enum.sort_by(& &1.level)

  defp identities do
    for {schema, codes} <- [{Avatar, @avatars}, {Skill, @ultimates ++ @normals}, {Item, @items}, {Skin, @skins}] do
      query = from r in schema, where: r.code in ^codes, order_by: r.id, select: r.id
      query = if schema == Skin, do: query, else: from(r in query, where: is_nil(r.resource_uuid))
      {schema, Repo.all(query)}
    end
  end
end
