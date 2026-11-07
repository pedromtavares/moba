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

  def add_pick(player, selected_team, hero_id) do
    Repo.transaction(fn ->
      team = lock_team!(player, selected_team) |> load_picks()
      pick_ids = Enum.map(team.picks, & &1.id)

      if length(pick_ids) >= 3 || hero_id in pick_ids ||
           Game.Matches.selectable_heroes(%{generated_picks: []}, player, [hero_id]) == [],
         do: Repo.rollback(:invalid_pick)

      update_team!(team, %{pick_ids: pick_ids ++ [hero_id]})
    end)
  end

  def reorder_lineup(player, selected_team, hero_ids) do
    Repo.transaction(fn ->
      team = lock_team!(player, selected_team)
      visible_ids = Enum.map(selected_team.picks, & &1.id)

      if Enum.take(team.pick_ids, 3) != selected_team.pick_ids || Enum.sort(visible_ids) !== Enum.sort(hero_ids),
        do: Repo.rollback(:lineup_changed)

      update_team!(team, %{pick_ids: hero_ids})
    end)
  end

  defp lock_team!(player, team) do
    Repo.one(
      from t in Team,
        where: t.id == ^team.id and t.player_id == ^player.id,
        lock: "FOR UPDATE"
    ) || Repo.rollback(:not_found)
  end

  def import_training_team!(%{league_tier: tier, hero_ids: ids} = record)
      when tier >= 3 and length(ids) == 3 do
    player = Game.get_player!(record.player_id)

    %Team{
      player_id: player.id,
      training_team_id: record.id,
      pick_ids: ids,
      name: record.name || Moba.Utils.username(player)
    }
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :training_team_id)
  end

  def import_training_team!(_), do: :ok

  defp load_picks(teams) when is_list(teams) do
    hero_ids = Enum.map(teams, & &1.pick_ids) |> List.flatten()
    heroes = Game.get_heroes(hero_ids)

    Enum.map(teams, fn team ->
      picks =
        Enum.map(Enum.take(team.pick_ids, 3), fn pick_id ->
          Enum.find(heroes, &(&1.id == pick_id))
        end)
        |> Enum.filter(& &1)

      Map.merge(team, %{picks: picks, pick_ids: Enum.take(team.pick_ids, 3)})
    end)
  end

  defp load_picks(team) do
    heroes = Game.get_heroes(team.pick_ids)

    picks =
      Enum.map(Enum.take(team.pick_ids, 3), fn pick_id ->
        Enum.find(heroes, &(&1.id == pick_id))
      end)
      |> Enum.filter(& &1)

    Map.merge(team, %{picks: picks, pick_ids: Enum.take(team.pick_ids, 3)})
  end
end
