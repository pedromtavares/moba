defmodule Moba.Cleaner do
  import Ecto.Query, only: [from: 2]

  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.Hero
  alias Engine.Schema.Battle

  def cleanup_old_records do
    ago = Timex.now() |> Timex.shift(days: -7)
    query = from b in Battle, where: b.inserted_at <= ^ago, order_by: b.id, limit: 50

    Repo.all(query) |> delete_records()

    query = from h in Hero, where: h.inserted_at <= ^ago, where: is_nil(h.user_id), limit: 50

    Repo.all(query) |> delete_records()

    query =
      from h in Hero,
        where: not is_nil(h.archived_at),
        where: h.archived_at <= ^ago,
        where: not h.finished_pve,
        limit: 50

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
