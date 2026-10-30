defmodule Moba.Content.SeedCatalogTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @catalog @root |> Path.join("priv/repo/seed_catalog.json") |> File.read!() |> Jason.decode!()
  @art_root Path.join(@root, "priv/resources/original")
  @manifest @art_root |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

  test "contains the complete enabled development catalog and the boss" do
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

  test "matches the reviewed combat fixture for every skill rank and item" do
    fixture = @root |> Path.join("test/fixtures/engine_resources.json") |> File.read!() |> Jason.decode!()

    for kind <- ~w(skills items), expected <- fixture[kind] do
      actual = Enum.find(@catalog[kind], &(&1["code"] == expected["code"] && &1["level"] == expected["level"]))
      assert actual, "Missing #{kind} #{expected["code"]} rank #{expected["level"]}"
      assert Map.take(actual, Map.keys(expected)) == expected
    end
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
