defmodule Moba.Cleaner do
  import Ecto.Query, only: [from: 2]

  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.{Hero, Skill, Item, Avatar}
  alias Engine.Schema.Battle

  def cleanup_old_records do
    ago = Timex.now() |> Timex.shift(days: -7)
    query = from b in Battle, where: b.inserted_at <= ^ago, where: b.type != "duel", order_by: b.id, limit: 50

    Repo.all(query) |> delete_records()

    query = from h in Hero,
      where: is_nil(h.finished_at),
      where: is_nil(h.archived_at),
      where: h.inserted_at <= ^ago,
      where: is_nil(h.bot_difficulty)

    Repo.update_all(query, set: [archived_at: DateTime.utc_now()])

    query =
      from h in Hero,
        where: not is_nil(h.archived_at),
        where: h.archived_at <= ^ago,
        where: is_nil(h.finished_at),
        where: h.bot_difficulty != "boss",
        limit: 50

    Repo.all(query) |> delete_records()

    query =
      from s in Avatar,
        where: s.inserted_at <= ^ago,
        where: s.current == false,
        where: not is_nil(s.match_id),
        limit: 50

    Repo.all(query) |> delete_records()

    query =
      from s in Skill, where: s.inserted_at <= ^ago, where: s.current == false, where: not is_nil(s.match_id), limit: 50

    Repo.all(query) |> delete_records()

    query =
      from s in Item, where: s.inserted_at <= ^ago, where: s.current == false, where: not is_nil(s.match_id), limit: 50

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
