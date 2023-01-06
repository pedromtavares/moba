defmodule Moba.Game.Teams do
  @moduledoc """
  Manages Team records and queries.
  See Moba.Game.Schema.Team for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Team
  import Ecto.Query, only: [from: 2]

  def list_teams(player_id, defensive) do
    from(t in Team, where: t.player_id == ^player_id, where: t.defensive == ^defensive) |> Repo.all() |> load_picks()
  end

  def list_teams(player), do: Repo.preload(player, :teams) |> Map.get(:teams) |> load_picks()

  def create_team!(attrs) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert!()
    |> load_picks()
  end

  def delete_team!(team) do
    Repo.delete(team)
  end

  def update_team!(team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update!()
    |> load_picks()
  end

  defp load_picks(teams) when is_list(teams) do
    hero_ids = Enum.map(teams, & &1.pick_ids) |> List.flatten()
    heroes = Game.get_heroes(hero_ids)

    Enum.map(teams, fn team ->
      picks =
        Enum.map(team.pick_ids, fn pick_id ->
          Enum.find(heroes, &(&1.id == pick_id))
        end)

      Map.put(team, :picks, picks)
    end)
  end

  defp load_picks(team) do
    heroes = Game.get_heroes(team.pick_ids)

    picks =
      Enum.map(team.pick_ids, fn pick_id ->
        Enum.find(heroes, &(&1.id == pick_id))
      end)

    Map.put(team, :picks, picks)
  end
end
