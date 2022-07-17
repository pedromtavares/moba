defmodule Moba.Game.Schema.Duel do
  @moduledoc """

  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Accounts, Engine, Game}
  alias Game.Schema.{Hero, Player}
  alias Accounts.Schema.User

  schema "duels" do
    field :phase, :string
    field :type, :string
    field :phase_changed_at, :utc_datetime
    field :auto, :boolean

    embeds_one :rewards, Engine.Schema.Rewards, on_replace: :update

    belongs_to :user, User
    belongs_to :opponent, User
    belongs_to :winner, User

    belongs_to :player, Player
    belongs_to :opponent_player, Player
    belongs_to :winner_player, Player

    belongs_to :player_first_pick, Hero
    belongs_to :opponent_first_pick, Hero
    belongs_to :player_second_pick, Hero
    belongs_to :opponent_second_pick, Hero

    timestamps()
  end

  def changeset(duel, attrs) do
    duel
    |> cast(attrs, [
      :auto,
      :type,
      :phase,
      :user_id,
      :opponent_id,
      :player_first_pick_id,
      :opponent_first_pick_id,
      :player_second_pick_id,
      :opponent_second_pick_id,
      :winner_id,
      :phase_changed_at,
      :player_id,
      :opponent_player_id,
      :winner_player_id
    ])
    |> cast_embed(:rewards)
  end
end
