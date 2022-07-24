defmodule Moba.Repo.Migrations.CreateSeasons do
  use Ecto.Migration
  alias Moba.{Game, Repo}
  alias Game.Schema.Season

  def up do
    create table(:seasons) do
      add :title, :string
      add :changelog, :text
      add :active, :boolean, default: false
      add :last_server_update_at, :utc_datetime
      add :resource_uuid, :string

      timestamps()
    end

    create index(:seasons, [:active])

    alter table(:skills) do
      add :resource_uuid, :string
    end

    create index(:skills, [:resource_uuid])

    alter table(:items) do
      add :resource_uuid, :string
    end

    create index(:items, [:resource_uuid])

    alter table(:avatars) do
      add :resource_uuid, :string
    end

    create index(:avatars, [:resource_uuid])

    flush()

    uuid = UUID.uuid1()

    active_season =
      Repo.insert!(%Season{
        active: true,
        resource_uuid: uuid,
        last_server_update_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    create table(:players) do
      add :status, :string
      add :ranking, :integer
      add :tutorial_step, :integer, default: 1
      add :duel_score, :map, default: %{}
      add :hero_collection, :jsonb, default: "[]"
      add :pvp_tier, :integer, default: 0
      add :pvp_points, :integer, default: 0
      add :pve_tier, :integer, default: 0
      add :match_history, :map, default: %{}
      add :last_challenge_at, :utc_datetime
      add :bot_options, :map
      add :preferences, :map, default: %{}
      add :pve_progression, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all)
      add :season_id, references(:seasons, on_delete: :nothing)
      add :current_pve_hero_id, references(:heroes, on_delete: :nothing)
      add :total_farm, :integer, default: 0

      timestamps()
    end

    create index(:players, [:user_id])
    create index(:players, [:pvp_points])
    create unique_index(:players, [:user_id, :season_id])

    alter table(:heroes) do
      add :player_id, references(:players, on_delete: :delete_all)
    end

    alter table(:quest_progressions) do
      add :player_id, references(:players, on_delete: :delete_all)
    end

    alter table(:duels) do
      add :player_id, references(:players, on_delete: :delete_all)
      add :opponent_player_id, references(:players, on_delete: :delete_all)
      add :winner_player_id, references(:players, on_delete: :delete_all)
    end

    rename table("duels"), :user_first_pick_id, to: :player_first_pick_id
    rename table("duels"), :user_second_pick_id, to: :player_second_pick_id
  end

  def down do
    rename table(:duels), :player_first_pick_id, to: :user_first_pick_id
    rename table(:duels), :player_second_pick_id, to: :user_second_pick_id

    alter table(:heroes) do
      remove :player_id
    end

    alter table(:quest_progressions) do
      remove :player_id
    end

    alter table(:duels) do
      remove :player_id
      remove :opponent_player_id
      remove :winner_player_id
    end

    drop table(:players)
    drop table(:seasons)

    alter table(:skills) do
      remove :resource_uuid
    end

    alter table(:items) do
      remove :resource_uuid
    end

    alter table(:avatars) do
      remove :resource_uuid
    end
  end
end
