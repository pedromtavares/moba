defmodule Mix.Tasks.Cleanup do
  use Mix.Task
  alias Moba.Repo

  import Ecto.Query, only: [from: 2]

  @shortdoc "Deletes old battles and heroes"
  def run(_) do
    Mix.Task.run("app.start")

    run_query()
  end

  def run_query() do
    IO.puts("Fetching another batch...")
    ago = Timex.now() |> Timex.shift(days: -7)
    query = from b in Moba.Engine.Schema.Battle, where: b.inserted_at <= ^ago, order_by: b.id, limit: 50

    Repo.all(query) |> delete()

    query = from h in Moba.Game.Schema.Hero, where: h.inserted_at <= ^ago, where: is_nil(h.user_id), limit: 50

    Repo.all(query) |> delete()
  end

  def delete(results) when length(results) > 0 do
    Enum.map(results, fn record ->
      IO.puts("Deleting #{record.__struct__} ##{record.id}")
      Repo.delete(record)
    end)

    run_query()
  end

  def delete(_) do
    IO.puts("Cleanup done!")
  end
end
