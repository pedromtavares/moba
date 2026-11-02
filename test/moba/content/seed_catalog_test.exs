defmodule Moba.Content.SeedCatalogTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @catalog @root |> Path.join("priv/repo/seed_catalog.json") |> File.read!() |> Jason.decode!()
  @art_root Path.join(@root, "priv/resources/original")
  @manifest @art_root |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

  test "contains the complete enabled production catalog and the boss" do
    assert length(@catalog["avatars"]) == 25
    assert length(@catalog["items"]) == 30
    assert length(@catalog["skills"]) == 196

    for kind <- ~w(avatars items skills), row <- @catalog[kind] do
      assert is_nil(row["resource_uuid"])
      assert row["current"] == false
      refute Map.has_key?(row, "id")
      refute Map.has_key?(row, "image")
      refute Map.has_key?(row, "background")
      assert row["enabled"] || row["code"] == "boss" || String.starts_with?(row["code"], "boss_")
    end

    for avatar <- @catalog["avatars"] do
      assert Enum.any?(@catalog["skills"], fn skill ->
               skill["code"] == avatar["ultimate_code"] && skill["level"] == 1 && skill["ultimate"]
             end)
    end
  end

  test "contains every skill rank and item in the frozen combat fixture" do
    fixture = @root |> Path.join("test/fixtures/engine_resources.json") |> File.read!() |> Jason.decode!()

    # Combat regressions retain their reviewed balance; fresh installs use production balance.
    for kind <- ~w(skills items) do
      identity = &{&1["code"], &1["level"]}
      assert MapSet.subset?(MapSet.new(fixture[kind], identity), MapSet.new(@catalog[kind], identity))
    end
  end

  test "uses production skill balance across ranks" do
    for {code, fields, expected} <- [
          {"dream_coil", ~w(cooldown base_damage), [[4, 150], [3, 250], [2, 350]]},
          {"rearm", ~w(mp_cost cooldown power_amount), [[20, 4, 0], [30, 3, 10], [40, 2, 20]]},
          {"fury_swipes", ~w(duration base_damage), [[2, 1], [2, 2], [2, 3], [2, 4], [2, 5]]},
          {"phase_shift", ~w(cooldown roll_number), [[4, 20], [3, 20], [2, 20], [1, 20], [0, 20]]},
          {"spell_steal", ~w(cooldown power_amount atk_multiplier), [[2, 35, 1.5], [2, 50, 1.5], [2, 65, 1.5]]}
        ] do
      actual =
        @catalog["skills"]
        |> Enum.filter(&(&1["code"] == code))
        |> Enum.sort_by(& &1["level"])
        |> Enum.map(fn skill -> Enum.map(fields, &Map.fetch!(skill, &1)) end)

      assert actual == expected, "Production balance mismatch for #{code}"
    end

    assert Enum.find(@catalog["skills"], &(&1["code"] == "boss_ult"))["armor_amount"] == 7
  end

  test "uses production item balance and avatar unlock levels" do
    for {code, fields, expected} <- [
          {"bkb", ~w(mp_cost cooldown), [3, 4]},
          {"daedalus", ~w(roll_number), [25]},
          {"dagon", ~w(mp_cost cooldown), [5, 4]},
          {"dagon5", ~w(mp_cost cooldown), [15, 4]},
          {"diffusal_blade", ~w(mp_multiplier other_mp_multiplier), [0.05, 0.05]},
          {"heavens_halberd", ~w(cooldown), [4]},
          {"linkens_sphere", ~w(cooldown), [4]},
          {"orchid_malevolence", ~w(cooldown armor_amount), [3, 30]},
          {"satanic", ~w(mp_cost cooldown), [5, 4]},
          {"scythe_of_vyse", ~w(mp_cost cooldown), [15, 4]},
          {"shivas_guard", ~w(cooldown armor_amount), [4, 40]},
          {"silver_edge", ~w(base_amount), [150]}
        ] do
      item = Enum.find(@catalog["items"], &(&1["code"] == code))
      assert Enum.map(fields, &Map.fetch!(item, &1)) == expected, "Production balance mismatch for #{code}"
    end

    assert Enum.find(@catalog["avatars"], &(&1["code"] == "tinker"))["level_requirement"] == 13
  end

  test "new content retains its Tavern unlock requirements" do
    for code <- ~w(anti_mage bloodseeker leshrac terrorblade) do
      assert Enum.find(@catalog["avatars"], &(&1["code"] == code))["level_requirement"] == 1
    end

    for code <- ~w(chakra_magic fortunes_end purifying_flames) do
      assert Enum.all?(Enum.filter(@catalog["skills"], &(&1["code"] == code)), &(&1["level_requirement"] == 1))
    end
  end

  test "every playable hero has one distinct Master and Grandmaster skin" do
    assert length(@catalog["skins"]) == 48
    assert length(Enum.uniq_by(@catalog["skins"], & &1["code"])) == 48

    for avatar <- Enum.filter(@catalog["avatars"], & &1["enabled"]) do
      skins = Enum.filter(@catalog["skins"], &(&1["avatar_code"] == avatar["code"]))
      assert Enum.sort(Enum.map(skins, & &1["league_tier"])) == [5, 6]
      assert length(Enum.uniq_by(skins, & &1["artwork"])) == 2
      assert Enum.all?(skins, &(&1["author_name"] == "AI" && &1["author_link"] == "https://chat.com"))
    end
  end

  test "every artwork reference resolves to an original generated asset" do
    paths =
      Enum.flat_map(@catalog["avatars"], &["heroes/#{&1["code"]}/default.webp"]) ++
        Enum.map(@catalog["skins"], & &1["artwork"]) ++
        Enum.map(@catalog["items"], &"items/#{&1["code"]}.webp") ++
        Enum.map(Enum.uniq_by(@catalog["skills"], & &1["code"]), &"skills/#{&1["code"]}.webp")

    assert MapSet.new(paths) == MapSet.new(@manifest["assets"], & &1["path"])

    hashes =
      for path <- paths do
        binary = File.read!(Path.join(@art_root, path))
        assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = binary
        assert byte_size(binary) > 5_000
        :crypto.hash(:sha256, binary)
      end

    assert length(Enum.uniq(hashes)) == length(paths)

    for avatar <- @catalog["avatars"] do
      assert File.regular?(Path.join(@art_root, "heroes/#{avatar["code"]}/portrait.webp"))
    end
  end
end
