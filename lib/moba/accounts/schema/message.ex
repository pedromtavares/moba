defmodule Moba.Accounts.Schema.Message do
  @moduledoc """
  Message schema, used in the sidebar Chat.
   - tier is used to show the current hero's current League
   - code refers to an Avatar code or any other resource
  """
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset
  alias Moba.Accounts

  schema "messages" do
    field :image, Moba.Image.Type
    field :code, :string

    field :tier, :integer
    field :author, :string
    field :body, :string
    field :is_admin, :boolean

    belongs_to :user, Accounts.Schema.User

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:image, :code, :tier, :author, :body, :user_id, :is_admin])
    |> validate_length(:body, min: 2, max: 500)
  end
end
