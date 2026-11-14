defmodule Moba.Game.CommunityActivity do
  @moduledoc "Recent, player-driven activity for the community list."

  import Ecto.Query
  import Moba.Utils, only: [username: 1]

  alias Moba.Repo
  alias Moba.Game.Query.HeroQuery
  alias Moba.Game.Schema.{Duel, Hero, Match, Player}

  def latest_for_players(player_ids, training_teams \\ %{})

  def latest_for_players([], _training_teams), do: %{}

  def latest_for_players(player_ids, training_teams) do
    since = DateTime.add(DateTime.utc_now(), -604_800, :second)

    (team_activity(training_teams, since) ++
       training_activity(player_ids, since, :finished_at) ++
       training_activity(player_ids, since, :inserted_at) ++
       match_activity(player_ids, since) ++
       duel_activity(player_ids, since, :player_id) ++
       duel_activity(player_ids, since, :opponent_player_id))
    |> Enum.map(&Map.update!(&1, :at, fn at -> utc_timestamp(at) end))
    |> Enum.sort_by(
      fn activity ->
        {DateTime.to_unix(activity.at), activity_priority(activity), activity.id}
      end,
      :desc
    )
    |> Enum.reduce(%{}, fn activity, activities -> Map.put_new(activities, activity.player_id, activity) end)
    |> load_pvp_rosters()
  end

  defp load_pvp_rosters(activities) do
    ids =
      activities
      |> Map.values()
      |> Enum.flat_map(&Map.get(&1, :pvp_pick_ids, []))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    heroes =
      if ids == [] do
        %{}
      else
        from(h in HeroQuery.load_avatar(),
          where: h.id in ^ids,
          select: struct(h, [:id, :level, :avatar_id, :skin_id])
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
      end

    Map.new(activities, fn {player_id, activity} ->
      case Map.pop(activity, :pvp_pick_ids) do
        {nil, activity} ->
          {player_id, activity}

        {picks, activity} ->
          roster = for id <- picks, hero = heroes[id], do: hero
          {player_id, Map.put(activity, :pvp_roster, roster)}
      end
    end)
  end

  defp activity_priority(%{kind: :training_started, team_name: _}), do: 1
  defp activity_priority(%{kind: :training_started}), do: 0
  defp activity_priority(_), do: 2

  def live_player_ids(online_ids) do
    from(p in Player, where: p.id in ^online_ids and p.status == "available", select: p.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp training_activity(player_ids, since, time_field) do
    from(h in Hero,
      where: h.player_id in ^player_ids and is_nil(h.training_team_id) and field(h, ^time_field) >= ^since,
      distinct: h.player_id,
      order_by: [asc: h.player_id, desc: field(h, ^time_field), desc: h.id],
      preload: [:avatar]
    )
    |> Repo.all()
    |> Enum.map(fn hero ->
      %{
        player_id: hero.player_id,
        kind: if(time_field == :finished_at, do: :training_finished, else: :training_started),
        id: hero.id,
        at: Map.fetch!(hero, time_field),
        avatar: hero.avatar.name
      }
    end)
  end

  defp team_activity(teams, since) do
    for {_player_id, team} <- teams,
        {kind, at} <- [training_started: team.started_at, training_finished: team.finished_at],
        at && DateTime.compare(utc_timestamp(at), since) != :lt do
      %{
        player_id: team.player_id,
        kind: kind,
        id: team.id,
        at: at,
        team_name: team.name,
        league_tier: team.league_tier
      }
    end
  end

  defp match_activity(player_ids, since) do
    from(m in Match,
      where: m.player_id in ^player_ids and m.type == "manual" and m.phase == "scored",
      where: m.updated_at >= ^since,
      distinct: m.player_id,
      order_by: [asc: m.player_id, desc: m.updated_at, desc: m.id],
      preload: [opponent: :user]
    )
    |> Repo.all()
    |> Enum.map(fn match ->
      %{
        player_id: match.player_id,
        kind: :match,
        id: match.id,
        at: match.updated_at,
        opponent: username(match.opponent),
        result: result(match.winner_id, match.player_id),
        pvp_pick_ids: match.player_picks || []
      }
    end)
  end

  defp duel_activity(player_ids, since, owner_field) do
    query =
      from(d in Duel,
        where: field(d, ^owner_field) in ^player_ids and d.phase == "finished",
        where: is_nil(d.type) or d.type == "pvp",
        where: d.updated_at >= ^since,
        distinct: field(d, ^owner_field),
        order_by: [asc: field(d, ^owner_field), desc: d.updated_at, desc: d.id],
        preload: [player: :user, opponent_player: :user]
      )

    query =
      if owner_field == :opponent_player_id,
        do: from(d in query, where: is_nil(d.auto) or d.auto == false),
        else: query

    query
    |> Repo.all()
    |> Enum.map(fn duel ->
      player_id = Map.fetch!(duel, owner_field)

      {opponent, picks} =
        if owner_field == :player_id do
          {duel.opponent_player, [duel.player_first_pick_id, duel.player_second_pick_id]}
        else
          {duel.player, [duel.opponent_first_pick_id, duel.opponent_second_pick_id]}
        end

      %{
        player_id: player_id,
        kind: if(duel.auto, do: :season_duel, else: :live_duel),
        id: duel.id,
        at: duel.updated_at,
        opponent: username(opponent),
        result: result(duel.winner_player_id, player_id),
        pvp_pick_ids: picks
      }
    end)
  end

  defp result(nil, _player_id), do: :draw
  defp result(winner_id, player_id) when winner_id == player_id, do: :won
  defp result(_, _), do: :lost

  defp utc_timestamp(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc_timestamp(%DateTime{} = at), do: at
end
