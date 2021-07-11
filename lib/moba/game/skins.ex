defmodule Moba.Game.Skins do
  @moduledoc """
  Manages Skin records and queries.
  See Moba.Game.Schema.Skin for more info.

  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Skin

  import Ecto.Query, only: [from: 2]

  def list_for(avatar_code) do
    Repo.all(from skin in Skin, where: skin.avatar_code == ^avatar_code, order_by: [asc: :league_tier])
  end

  def get_by_code!(code), do: Repo.get_by!(Skin, code: code)

  def list_with_codes([]), do: []
  def list_with_codes(codes), do: Repo.all(from skin in Skin, where: skin.code in ^codes)

  def default(avatar_code) do
    %Skin{
      code: "default",
      id: nil,
      avatar_code: avatar_code
    }
  end
end
