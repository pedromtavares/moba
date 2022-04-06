defmodule Moba.Accounts.Schema.Message do
  @moduledoc """
  Message schema, used in the season message board.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.Accounts

  schema "messages" do
    field :author, :string
    field :title, :string
    field :body, :string
    field :channel, :string
    field :tier, :integer
    field :is_admin, :boolean

    belongs_to :user, Accounts.Schema.User

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:author, :title, :body, :channel, :tier, :is_admin, :user_id])
  end
end
