defmodule Moba.Cleaner do
  import Ecto.Query, only: [from: 2]

  alias Moba.{Repo, Game, Engine, Accounts}
  alias Game.Query.HeroQuery
  alias Game.Schema.Hero
  alias Engine.Schema.Battle
  alias Accounts.Schema.User

  def cleanup_old_records do
    ago = Timex.now() |> Timex.shift(days: -7)
    query = from b in Battle, where: b.inserted_at <= ^ago, order_by: b.id, limit: 50

    Repo.all(query) |> delete_records()

    query = from h in Hero, where: h.inserted_at <= ^ago, where: is_nil(h.user_id), limit: 50

    Repo.all(query) |> delete_records()

    query = from h in Hero, where: not is_nil(h.archived_at), where: h.archived_at <= ^ago, limit: 50

    Repo.all(query) |> delete_records()

    archive_weak_heroes()
  end

  defp delete_records(results) when length(results) > 0 do
    Enum.map(results, fn record ->
      IO.puts("Deleting #{record.__struct__} ##{record.id}")
      Repo.delete(record)
    end)

    cleanup_old_records()
  end

  defp delete_records(_), do: nil

  defp archive_weak_heroes do
    base = HeroQuery.non_bots() |> HeroQuery.unarchived()

    query = from hero in base,
      join: user in User, on: hero.user_id == user.id,
      where: hero.league_tier < 4 or is_nil(hero.league_tier),
      where: is_nil(user.current_pve_hero_id) or user.current_pve_hero_id != hero.id

    Repo.update_all(query, [set: [archived_at: DateTime.utc_now()]])
  end
end
