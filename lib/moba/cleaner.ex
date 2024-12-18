defmodule Moba.Cleaner do
  @moduledoc """
  Module dedicated to cleaning up unused records, runs daily by the Conductor
  """
  import Ecto.Query, only: [from: 2]

  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.{Duel, Player, Hero, Skill, Item, Avatar, Match}
  alias Engine.Schema.Battle

  def cleanup_old_records do
    IO.puts("Cleaning up records...")
    last_hour = Timex.now() |> Timex.shift(hours: -1)

    # deletes duels that have not finished within the hour
    query = from d in Duel, where: d.inserted_at <= ^last_hour, where: d.phase != "finished", order_by: d.id, limit: 20
    Repo.all(query) |> delete_records()

    last_week = Timex.now() |> Timex.shift(days: -7)

    # deletes all non-duel battles from over a week ago
    query = from b in Battle, where: b.inserted_at <= ^last_week, where: b.type != "duel", order_by: b.id, limit: 20
    Repo.all(query) |> delete_records()

    # deletes non-current avatars that are over a week old
    query =
      from s in Avatar,
        where: s.inserted_at <= ^last_week,
        where: s.current == false,
        where: not is_nil(s.resource_uuid),
        limit: 20

    Repo.all(query) |> delete_records()

    # deletes non-current skills that are over a week old
    query =
      from s in Skill,
        where: s.inserted_at <= ^last_week,
        where: s.current == false,
        where: not is_nil(s.resource_uuid),
        limit: 20

    Repo.all(query) |> delete_records()

    # deletes non-current items that are over a week old
    query =
      from s in Item,
        where: s.inserted_at <= ^last_week,
        where: s.current == false,
        where: not is_nil(s.resource_uuid),
        limit: 20

    Repo.all(query) |> delete_records()

    # archives all unfinished heroes that are over a week old
    query =
      from h in Hero,
        join: player in assoc(h, :player),
        where: h.id != player.current_pve_hero_id,
        where: is_nil(h.finished_at),
        where: is_nil(h.archived_at),
        where: h.inserted_at <= ^last_week,
        where: is_nil(h.bot_difficulty)

    Repo.update_all(query, set: [archived_at: DateTime.utc_now()])

    # sets current_pve_hero_id of all inactive players to nil after a week
    query =
      from p in Player,
        where: not is_nil(p.user_id),
        join: user in assoc(p, :user),
        where: is_nil(user.last_online_at) or user.last_online_at < ^last_week

    Repo.update_all(query, set: [current_pve_hero_id: nil])

    # sets current_pve_hero_id of all inactive guests to nil after a week
    query = from p in Player, where: is_nil(p.user_id), where: p.inserted_at < ^last_week
    Repo.update_all(query, set: [current_pve_hero_id: nil])

    # archives all guest heroes after a week
    query =
      from h in Hero,
        join: player in assoc(h, :player),
        where: is_nil(player.user_id),
        where: player.inserted_at < ^last_week,
        where: is_nil(h.archived_at),
        where: is_nil(h.bot_difficulty)

    Repo.update_all(query, set: [archived_at: DateTime.utc_now()])

    # deletes heroes that have been archived for over a week
    query =
      from h in Hero,
        where: not is_nil(h.archived_at),
        where: h.archived_at <= ^last_week,
        where: is_nil(h.bot_difficulty) or h.bot_difficulty != "boss",
        limit: 20

    Repo.all(query) |> delete_records()

    # deletes matches from > a week ago

    query =
      from m in Match,
        where: m.inserted_at <= ^last_week,
        limit: 20

    Repo.all(query) |> delete_records()
  end

  defp delete_records(results) when length(results) > 0 do
    Enum.map(results, fn record ->
      IO.puts("Deleting #{record.__struct__} ##{record.id}")
      Repo.delete(record)
    end)

    cleanup_old_records()
  end

  defp delete_records(_), do: nil
end
