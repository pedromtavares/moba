defmodule Moba.Accounts.Schema.Discord do
  @moduledoc """
  Used to store bot-specific options for players
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :nickname, :string
    field :avatar, :string
    field :id, :string
    field :token, :string
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :nickname,
      :avatar,
      :id,
      :token
    ])
  end
end
