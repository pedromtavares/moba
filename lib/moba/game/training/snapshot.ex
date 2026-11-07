defmodule Moba.Game.Training.Snapshot do
  @moduledoc "Server-owned training snapshots with frozen loadouts and replay state."

  # Safe ETF decoding requires even retired atoms in existing snapshots to be loaded.
  # Only these fixed names are interned, never names taken from the snapshot.
  @legacy_snapshot_atoms ~w(buyback_version hold lane reorder_unlocked reward_version sale structure_skill)

  def encode(state), do: :erlang.term_to_binary(state, [:compressed])

  def decode(binary) do
    Enum.each(@legacy_snapshot_atoms, &String.to_atom/1)

    Enum.each(
      [
        Moba.Game.TeamTraining,
        Moba.Game.Training.Loadouts,
        Moba.Game.Training.Combat,
        Moba.Game.TrainingEncounters,
        Moba.Game.Avatars,
        Moba.Game.Builds,
        Moba.Game.Schema.Hero,
        Moba.Game.Schema.Avatar,
        Moba.Game.Schema.Skill,
        Moba.Game.Schema.Item,
        Moba.Game.Schema.Player,
        Moba.Engine.Schema.Battle,
        Moba.Engine.Schema.Turn,
        Moba.Engine.Schema.Battler,
        Moba.Engine.Core.Buff,
        Moba.Engine.Core.Processor,
        Ecto.Schema.Metadata,
        Ecto.Association.NotLoaded
      ],
      &Code.ensure_loaded!/1
    )

    :erlang.binary_to_term(binary, [:safe])
  end

  def read(binary) when is_binary(binary) do
    case decode(binary) do
      state when is_map(state) -> {:ok, state}
      _ -> {:error, :invalid_snapshot}
    end
  rescue
    ArgumentError -> {:error, :invalid_snapshot}
  end

  def read(_), do: {:error, :invalid_snapshot}
end
