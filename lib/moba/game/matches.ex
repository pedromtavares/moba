defmodule Moba.Game.Matches do
  @moduledoc """
  Manages Match records and queries.
  See Moba.Game.Schema.Match for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Match
  import Ecto.Query, only: [from: 2]

  def current do
    Repo.all(from m in Match, where: m.active == true) |> List.first()
  end

  def last_active do
    Repo.all(from m in Match, where: m.active == false, order_by: [desc: m.id], limit: 1)
    |> List.first()
  end

  def create!(attrs \\ %{}) do
    %Match{active: true}
    |> Match.changeset(attrs)
    |> Repo.insert!()
  end

  def update!(%Match{} = match, attrs) do
    match
    |> Match.changeset(attrs)
    |> Repo.update!()
  end

  def load_podium(%{winners: winners}) do
    [winners["1"], winners["2"], winners["3"]]
    |> Enum.map(fn hero_id ->
      Game.get_hero!(hero_id)
    end)
    |> Enum.reject(fn hero -> is_nil(hero) end)
  end

  def load_podium(_), do: nil
end
