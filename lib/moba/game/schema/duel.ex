defmodule Moba.Game.Schema.Duel do
  @moduledoc """

  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Accounts, Engine, Game}
  alias Game.Schema.Hero

  schema "duels" do
    field :phase, :string

    embeds_one :rewards, Engine.Schema.Rewards, on_replace: :update

    belongs_to :user, Accounts.Schema.User
    belongs_to :opponent, Accounts.Schema.User
    belongs_to :winner, Accounts.Schema.User

    belongs_to :user_first_pick, Hero
    belongs_to :opponent_first_pick, Hero
    belongs_to :user_second_pick, Hero
    belongs_to :opponent_second_pick, Hero

    timestamps()
  end

  def changeset(duel, attrs) do
    duel
    |> cast(attrs, [
      :phase,
      :user_id,
      :opponent_id,
      :user_first_pick_id,
      :opponent_first_pick_id,
      :user_second_pick_id,
      :opponent_second_pick_id,
      :winner_id
    ])
    |> cast_embed(:rewards)
  end
end
