defmodule Moba.Game.ArenaPicks do
  @moduledoc """
  Manages ArenaPick records and queries.
  See Moba.Game.Schema.ArenaPick for more info.

  """

  alias Moba.{Repo, Game}
  alias Game.Schema.ArenaPick

  import Ecto.Query, only: [from: 2]

  def create!(%{current_pvp_hero: hero} = user, match) do
    ArenaPick.create_changeset(%ArenaPick{}, %{
      points: hero.pvp_points,
      wins: hero.pvp_wins,
      losses: hero.pvp_losses,
      ranking: hero.pvp_ranking
    }, user, hero, match)
    |> Repo.insert!()
  end

  def list_recent(%{id: user_id}) do
    Repo.all(from ap in ArenaPick, where: ap.user_id == ^user_id, limit: 7, order_by: [desc: ap.id])
    |> Repo.preload([hero: :avatar])
  end
end