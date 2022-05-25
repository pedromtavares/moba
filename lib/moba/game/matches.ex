defmodule Moba.Game.Matches do
  @moduledoc """
  Manages Match records and queries.
  See Moba.Game.Schema.Match for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Match
  import Ecto.Query, only: [from: 2]

  def current_match do
    Repo.all(from m in Match, where: m.active == true) |> List.first()
  end

  def last_match do
    Repo.all(from m in Match, where: m.active == false, order_by: [desc: m.id], limit: 1)
    |> List.first()
  end

  def create_match!(attrs) do
    %Match{active: true}
    |> Match.changeset(attrs)
    |> Repo.insert!()
  end

  def update_match!(%Match{} = match, attrs) do
    match
    |> Match.changeset(attrs)
    |> Repo.update!()
  end
end
