defmodule Moba.Game.CommunityActivity do
  @moduledoc "Recent, player-driven activity for the community list."

  import Ecto.Query
  import Moba.Utils, only: [username: 1]

  alias Moba.Repo
  alias Moba.Game.Schema.{Duel, Hero, Match, Player}

  def latest_for_players([]), do: %{}

  def latest_for_players(player_ids) do
    since = DateTime.add(DateTime.utc_now(), -604_800, :second)

    (training_activity(player_ids, since, :finished_at) ++
       training_activity(player_ids, since, :inserted_at) ++
       match_activity(player_ids, since) ++
       duel_activity(player_ids, since, :player_id) ++
       duel_activity(player_ids, since, :opponent_player_id))
    |> Enum.map(&Map.update!(&1, :at, fn at -> utc_timestamp(at) end))
    |> Enum.sort_by(
      fn activity ->
        {DateTime.to_unix(activity.at), if(activity.kind == :training_started, do: 0, else: 1), activity.id}
      end,
      :desc
    )
    |> Enum.reduce(%{}, fn activity, activities -> Map.put_new(activities, activity.player_id, activity) end)
  end

  def live_player_ids(online_ids) do
    from(p in Player, where: p.id in ^online_ids and p.status == "available", select: p.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp training_activity(player_ids, since, time_field) do
    from(h in Hero,
      where: h.player_id in ^player_ids and field(h, ^time_field) >= ^since,
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
        result: result(match.winner_id, match.player_id)
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
      opponent = if owner_field == :player_id, do: duel.opponent_player, else: duel.player

      %{
        player_id: player_id,
        kind: if(duel.auto, do: :season_duel, else: :live_duel),
        id: duel.id,
        at: duel.updated_at,
        opponent: username(opponent),
        result: result(duel.winner_player_id, player_id)
      }
    end)
  end

  defp result(nil, _player_id), do: :draw
  defp result(winner_id, player_id) when winner_id == player_id, do: :won
  defp result(_, _), do: :lost

  defp utc_timestamp(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc_timestamp(%DateTime{} = at), do: at
end
