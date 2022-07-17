defmodule Moba.Repo.Migrations.CreateSeasons do
  use Ecto.Migration
  alias Moba.{Accounts, Game, Repo}
  alias Game.Schema.{Duel, Hero, Player, Season, QuestProgression}
  alias Accounts.Query.UserQuery
  alias Game.Query.{SkillQuery, ItemQuery, AvatarQuery, HeroQuery}
  import Ecto.Query

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

    AvatarQuery.current() |> Repo.update_all(set: [resource_uuid: uuid])
    SkillQuery.current() |> Repo.update_all(set: [resource_uuid: uuid])
    ItemQuery.current() |> Repo.update_all(set: [resource_uuid: uuid])

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

    flush()

    query = from(user in UserQuery.non_guests(), order_by: [asc: :id])
    users = Repo.all(query)

    Enum.each(users, fn user ->
      query = HeroQuery.with_user(Hero, user.id)
      total_xp_farm = Repo.aggregate(query, :sum, :total_xp_farm) || 0
      total_gold_farm = Repo.aggregate(query, :sum, :total_gold_farm) || 0

      bot_options =
        if user.is_bot do
          %{name: user.username, tier: user.bot_tier, codes: user.bot_codes}
        else
          nil
        end

      player =
        %Player{user_id: user.id, season_id: active_season.id}
        |> Player.changeset(%{
          ranking: user.ranking,
          hero_collection: user.hero_collection,
          pvp_tier: user.season_tier,
          pvp_points: user.season_points,
          pve_tier: user.pve_tier,
          match_history: user.match_history,
          last_challenge_at: user.last_challenge_at,
          current_pve_hero_id: user.current_pve_hero_id,
          shard_count: user.shard_count,
          status: user.status,
          tutorial_step: user.tutorial_step,
          preferences: Map.from_struct(user.preferences),
          bot_options: bot_options,
          total_farm: total_xp_farm + total_gold_farm
        })
        |> Repo.insert!()

      Repo.update_all(query, set: [player_id: player.id])

      progressions = from(qp in QuestProgression, where: qp.user_id == ^user.id)
      Repo.update_all(progressions, set: [player_id: player.id])

      update_pve_progression(player, progressions)
    end)

    duels = Repo.all(Duel)

    Enum.each(duels, fn duel ->
      player_id = player_for(duel.user_id)
      opponent_player_id = player_for(duel.opponent_id)

      winner_player_id =
        cond do
          duel.winner_id == duel.user_id -> player_id
          duel.winner_id == duel.opponent_id -> opponent_player_id
          true -> nil
        end

      Repo.update!(
        Duel.changeset(duel, %{
          player_id: player_id,
          opponent_player_id: opponent_player_id,
          winner_player_id: winner_player_id
        })
      )
    end)
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

  def player_for(nil), do: nil

  def player_for(user_id) do
    player = Repo.get_by(Player, user_id: user_id)
    if player, do: player.id, else: nil
  end

  def update_pve_progression(player, query) do
    progressions = Repo.all(query)
    season = Enum.find(progressions, &(&1.quest_id == 1))
    master = Enum.find(progressions, &(&1.quest_id == 24))
    grandmaster = Enum.find(progressions, &(&1.quest_id == 25))
    invoker = Enum.find(progressions, &(&1.quest_id == 26))

    pve_progression = %{
      season_codes: (season && season.history_codes) || [],
      master_codes: (master && master.history_codes) || [],
      grandmaster_codes: (grandmaster && grandmaster.history_codes) || [],
      invoker_codes: (invoker && invoker.history_codes) || []
    }

    codes = %{
      1 => 1,
      2 => 2,
      3 => 3,
      4 => 4,
      24 => 5,
      25 => 6,
      26 => 7
    }

    history =
      Enum.reduce(codes, %{}, fn {qid, tier}, acc ->
        qp = Enum.find(progressions, &(&1.quest_id == qid))

        if qp && qp.completed_at do
          Map.put(acc, tier, qp.completed_at)
        else
          acc
        end
      end)

    result = Map.put(pve_progression, :history, history)
    Game.update_player!(player, %{pve_progression: result})
  end
end
