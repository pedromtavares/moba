defmodule Moba.Game.Schema.Player do
  @moduledoc """
  Represents the Player, the link between a User and a Season. A player can be one of 3 options:
  - A real user: has a user_id
  - A guest: does not have a user_id
  - A bot: has the bot_options map set

  This is the main schema used throughout the app as it manages the heroes of a given player.
  Heroes and all other progression tracked in this schema are tied to a Season record, so when
  a new season starts, it will be a "fresh" start for everyone.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Accounts, Game}

  schema "players" do
    field :status, :string
    field :tutorial_step, :integer
    field :ranking, :integer
    field :duel_score, :map, default: %{}
    field :hero_collection, {:array, :map}
    field :pvp_tier, :integer, default: 0
    field :pvp_points, :integer, default: 0
    field :pve_tier, :integer, default: 0
    field :match_history, :map, default: %{}
    field :last_challenge_at, :utc_datetime
    field :total_farm, :integer, default: 0

    has_many :heroes, Game.Schema.Hero
    has_many :duels, Game.Schema.Duel

    belongs_to :current_pve_hero, Game.Schema.Hero
    belongs_to :season, Game.Schema.Season
    belongs_to :user, Accounts.Schema.User

    embeds_one :preferences, Game.Schema.Preferences, on_replace: :update
    embeds_one :bot_options, Game.Schema.BotOptions, on_replace: :update
    embeds_one :pve_progression, Game.Schema.PveProgression, on_replace: :update

    timestamps()
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [
      :status,
      :tutorial_step,
      :ranking,
      :duel_score,
      :hero_collection,
      :pvp_tier,
      :pvp_points,
      :pve_tier,
      :match_history,
      :last_challenge_at,
      :total_farm,
      :current_pve_hero_id,
      :user_id
    ])
    |> cast_embed(:preferences)
    |> cast_embed(:bot_options)
    |> cast_embed(:pve_progression)
  end
end
