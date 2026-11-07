defmodule Moba.TrainingSnapshotTest do
  use ExUnit.Case, async: true

  alias Moba.Game.Training.Snapshot

  test "a fresh VM can read legacy training keys and combat effects before other pages load them" do
    state = %{
      buyback_version: 2,
      reward_version: 1,
      reorder_unlocked: true,
      lane: :hold,
      structure_skill: nil,
      avatars: [%{display_defense: 1, display_magic: 2, display_offense: 3, display_speed: 4}],
      encounters: [%{battle_ids: [42], effects: [:healing_reduction, :healing_steal]}]
    }

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    script = """
    [encoded] = System.argv()
    binary = Base.decode64!(encoded)
    {:ok, decoded} = Moba.Game.Training.Snapshot.read(binary)
    2 = Map.fetch!(decoded, String.to_existing_atom("buyback_version"))
    [encounter] = Map.fetch!(decoded, String.to_existing_atom("encounters"))
    [42] = Map.fetch!(encounter, String.to_existing_atom("battle_ids"))
    """

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2" | paths] ++
          ["-e", script, "--", state |> Snapshot.encode() |> Base.encode64()],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "invalid ETF, non-map state, and unknown atoms are rejected safely" do
    name = "unknown_training_snapshot_atom_#{System.unique_integer([:positive])}"
    snapshot = <<131, 116, 1::32, 119, byte_size(name), name::binary, 97, 1>>

    for input <- [nil, <<131, 80, 0>>, Snapshot.encode([1, 2]), snapshot] do
      assert Snapshot.read(input) == {:error, :invalid_snapshot}
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end
end
