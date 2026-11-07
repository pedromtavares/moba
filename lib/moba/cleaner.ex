defmodule Moba.Cleaner do
  @moduledoc """
  Module dedicated to cleaning up unused records, runs daily by the Conductor
  """
  import Ecto.Query
  require Logger

  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.{Duel, Player, Hero, HeroSkill, HeroItem, Skill, Item, Avatar}
  alias Engine.Schema.Battle

  def cleanup_old_records do
    IO.puts("Cleaning up records...")
    last_hour = Timex.now() |> Timex.shift(hours: -1)

    # deletes duels that have not finished within the hour
    query = from d in Duel, where: d.inserted_at <= ^last_hour, where: d.phase != "finished", order_by: d.id, limit: 20
    delete_records(query)

    last_week = Timex.now() |> Timex.shift(days: -7)

    # deletes all non-duel battles from over a week ago
    query =
      from b in Battle,
        where: b.inserted_at <= ^last_week,
        where: b.type != "duel",
        where: is_nil(b.training_team_id),
        order_by: b.id,
        limit: 20

    delete_records(query)

    # deletes non-current avatars that are over a week old
    query =
      from s in Avatar,
        as: :resource,
        where: s.inserted_at <= ^last_week,
        where: s.current == false,
        where: not is_nil(s.resource_uuid),
        where: not exists(from h in Hero, where: h.avatar_id == parent_as(:resource).id),
        limit: 20

    delete_records(query)

    # deletes non-current skills that are over a week old
    query =
      from s in Skill,
        as: :resource,
        where: s.inserted_at <= ^last_week,
        where: s.current == false,
        where: not is_nil(s.resource_uuid),
        where:
          not exists(from a in Avatar, where: a.ultimate_id == parent_as(:resource).id) and
            not exists(from hs in HeroSkill, where: hs.skill_id == parent_as(:resource).id),
        limit: 20

    delete_records(query)

    # deletes non-current items that are over a week old
    query =
      from s in Item,
        as: :resource,
        where: s.inserted_at <= ^last_week,
        where: s.current == false,
        where: not is_nil(s.resource_uuid),
        where: not exists(from hi in HeroItem, where: hi.item_id == parent_as(:resource).id),
        limit: 20

    delete_records(query)

    # archives all unfinished heroes that are over a week old
    query =
      from h in Hero,
        join: player in assoc(h, :player),
        where: is_nil(player.current_pve_hero_id) or h.id != player.current_pve_hero_id,
        where: is_nil(h.finished_at),
        where: is_nil(h.archived_at),
        where: h.updated_at <= ^last_week,
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
    query =
      from p in Player,
        join: h in assoc(p, :current_pve_hero),
        where: is_nil(p.user_id) and p.updated_at < ^last_week,
        where: h.updated_at < ^last_week

    Repo.update_all(query, set: [current_pve_hero_id: nil])

    # archives all guest heroes after a week
    query =
      from h in Hero,
        join: player in assoc(h, :player),
        where: is_nil(player.user_id),
        where: player.updated_at < ^last_week and h.updated_at < ^last_week,
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

    delete_records(query)

    # Keep the recent 3v3 results used for win rate, even after their replays expire.
    Game.Matches.expired_matches(last_week)
    |> limit(20)
    |> delete_records()
  end

  defp delete_records(query, after_id \\ 0) do
    records = Repo.all(from r in exclude(query, :order_by), where: r.id > ^after_id, order_by: r.id)
    Enum.each(records, &delete_record/1)

    case List.last(records) do
      nil -> :ok
      record -> delete_records(query, record.id)
    end
  end

  defp delete_record(record) do
    changeset =
      record
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.foreign_key_constraint(:id, name: "_fkey", match: :suffix)

    # A reference may appear after the eligibility query. A savepoint keeps that
    # conflict from aborting other cleanup work, including in an outer transaction.
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.delete(changeset, mode: :savepoint, stale_error_field: :id)
      end)

    case result do
      {:ok, _} ->
        :ok

      {:error, _changeset} ->
        Logger.warning(
          "Cleanup retained referenced or concurrently changed #{inspect(record.__struct__)} ##{record.id}"
        )
    end
  end
end
