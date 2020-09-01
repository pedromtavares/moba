defmodule Moba.Accounts.Schema.Unlock do
  @moduledoc """
  Unlocks are basically rewards that users can get in exchange for shards
  in the Tavern. The resource is specified by resource_code.
  Currently Avatars and Skills can be unlocked.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.Accounts

  schema "unlocks" do
    field :resource_code, :string

    belongs_to :user, Accounts.Schema.User

    timestamps()
  end

  def changeset(unlock, attrs) do
    unlock
    |> cast(attrs, [:resource_code, :user_id])
  end
end
