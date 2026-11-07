defmodule Moba.Game.CreationPresetsTest do
  use Moba.DataCase, async: true

  test "all enabled skills are available without unlocks, including guest custom builds" do
    available = Game.list_creation_skills(1)
    codes = MapSet.new(available, & &1.code)

    for skill <- Game.list_normal_skills(), do: assert(skill.code in codes)

    assert MapSet.new(Game.list_creation_skills(1, ["echo_stomp", "mana_shield"]), & &1.id) ==
             MapSet.new(available, & &1.id)

    assert length(available) == MapSet.size(codes)
    avatar = Enum.find(Game.list_creation_avatars(), &(&1.code == "juggernaut"))

    ids =
      Enum.map(~w(echo_stomp mana_shield purifying_flames), fn code -> Enum.find(available, &(&1.code == code)).id end)

    assert {:ok, _, skills} = Game.Training.creation_loadout(nil, avatar.id, ids)
    assert MapSet.new(skills, & &1.code) == MapSet.new(~w(echo_stomp mana_shield purifying_flames))
  end

  test "updated presets have the requested names, ordering, skills and matching artwork" do
    expected = %{
      "tank" => [
        {"Regenerator", ~w(double_edge decay counter_helix)},
        {"Ninja Carry", ~w(shuriken_toss decay jinada)},
        {"Stomper", ~w(echo_stomp feast jinada)}
      ],
      "bruiser" => [
        {"Fury Bruiser", ~w(empower decay fury_swipes)},
        {"Ninja Bruiser", ~w(shuriken_toss jinada feast)},
        {"Full Power", ~w(empower double_edge fiery_soul)}
      ],
      "carry" => [
        {"Blink Striker", ~w(blink_strike decay feast)},
        {"Ninja Carry", ~w(shuriken_toss decay jinada)},
        {"Furious Blade", ~w(empower blade_fury fiery_soul)}
      ],
      "nuker" => [
        {"Destroyer", ~w(lightning_bolt death_pulse fiery_soul)},
        {"Purifier", ~w(purifying_flames maledict lightning_bolt)},
        {"Undying", ~w(mana_shield death_pulse phase_shift)}
      ],
      "support" => [
        {"Full Power", ~w(empower double_edge fiery_soul)},
        {"Purifier", ~w(purifying_flames maledict lightning_bolt)},
        {"Ninja Carry", ~w(shuriken_toss decay jinada)}
      ]
    }

    for {role, builds} <- expected do
      actual = Enum.map(Game.skill_builds_for(role), fn {skills, name} -> {name, Enum.map(skills, & &1.code)} end)
      assert actual == builds
      for {skills, _} <- Game.skill_builds_for(role), do: refute(hd(skills).passive)

      for {name, _} <- builds do
        path = MobaWeb.V2.Components.CreateComponents.invoke_build_art(name)
        assert File.exists?(Path.join("assets/static", path))
      end
    end
  end
end
