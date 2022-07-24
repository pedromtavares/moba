defmodule Moba.Game.Schema.Duel do
  @moduledoc """
  A set of 2 battles between two players. Before each battle starts, two heroes are picked:
  - Battle 1: Player picks first, opponent picks second
  - Battle 2: Opponent player picks first, player picks first
  This guarantees an opportunity for each player to outpick their opponent. Rewards are given
  at the end of the duel, which can end in a tie (1 win for each player). 
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Engine, Game}
  alias Game.Schema.{Hero, Player}

  schema "duels" do
    field :phase, :string
    field :type, :string
    field :phase_changed_at, :utc_datetime
    field :auto, :boolean

    embeds_one :rewards, Engine.Schema.Rewards, on_replace: :update

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
      :player_first_pick_id,
      :opponent_first_pick_id,
      :player_second_pick_id,
      :opponent_second_pick_id,
      :phase_changed_at,
      :player_id,
      :opponent_player_id,
      :winner_player_id
    ])
    |> cast_embed(:rewards)
  end
end
