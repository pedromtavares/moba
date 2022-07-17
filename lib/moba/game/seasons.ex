defmodule Moba.Game.Seasons do
  @moduledoc """
  Manages Season records and queries.
  See Moba.Game.Schema.Season for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Season
  import Ecto.Query, only: [from: 2]

  def current_season do
    Repo.all(from s in Season, where: s.active == true) |> List.first()
  end

  def last_season do
    Repo.all(from s in Season, where: s.active == false, order_by: [desc: s.id], limit: 1)
    |> List.first()
  end

  def update_season!(%Season{} = season, attrs) do
    season
    |> Season.changeset(attrs)
    |> Repo.update!()
  end
end
