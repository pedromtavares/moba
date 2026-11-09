defmodule Moba.Game.TeamRuns do
  @moduledoc "Owner-scoped persistent team-training drafts, runs and cinematic encounters."
  import Ecto.Query
  alias Moba.{Accounts, Game, Repo}
  alias Game.{TeamTraining, TrainingEncounters}
  alias Game.Training.{Loadouts, Snapshot}
  alias Game.Schema.{Player, TrainingTeam, TeamEncounter}

  def draft(scope, player) do
    Repo.transaction(fn ->
      player = scope |> players() |> where([p], p.id == ^player.id) |> lock("FOR UPDATE") |> Repo.one!()
      query = from r in owned(scope), where: r.player_id == ^player.id and r.phase == "draft", limit: 1

      case query |> lock("FOR UPDATE") |> Repo.one() do
        nil -> new_draft(scope, player)
        record -> resume_draft(scope, player, record)
      end
    end)
  end

  defp new_draft(scope, player) do
    %TrainingTeam{user_id: player.user_id, player_id: player.id}
    |> Ecto.Changeset.change(attributes(TeamTraining.draft(scope, player, Loadouts.catalog())))
    |> Repo.insert!()
  end

  defp resume_draft(scope, player, record) do
    case read_state(record) do
      {:ok, _} ->
        record

      {:error, :invalid_snapshot} ->
        record
        |> Ecto.Changeset.change(phase: "abandoned", archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update!()

        new_draft(scope, player)
    end
  end

  def latest(scope, player_id) do
    from(r in owned(scope), where: r.player_id == ^player_id and r.phase != "draft", order_by: [desc: r.id], limit: 1)
    |> Repo.one()
  end

  def list_training(scope, player_id, status, limit \\ Moba.base_hero_count()) do
    phases = if status == "finished", do: ["finished"], else: ["playing", "engagement"]

    from(r in owned(scope),
      where: r.player_id == ^player_id and r.phase in ^phases,
      order_by: [desc: r.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def active(scope, player_id) do
    from(r in owned(scope),
      where: r.player_id == ^player_id and r.phase in ["playing", "engagement"],
      order_by: [desc: r.id],
      limit: 1
    )
    |> Repo.one()
  end

  def scope(player), do: %{user: player.user, player_id: player.id}

  def start_guest!(key, pick) when is_map(pick) do
    {:ok, player} =
      guest_start(key, fn player, scope ->
        {:ok, record} = draft(scope, player)

        if state(record).picks == [] do
          __MODULE__.update(scope, record, &TeamTraining.add_pick(scope, &1, pick))
        end
      end)

    player
  end

  def start_guest_training(key, picks) do
    guest_start(key, fn player, scope ->
      unless latest(scope, player.id) do
        {:ok, record} = draft(scope, player)
        __MODULE__.update(scope, record, &TeamTraining.prepare_run(scope, &1, picks, nil))
      end
    end)
  end

  defp guest_start(key, start) do
    Repo.transaction(fn ->
      %Player{season_id: Game.current_season().id}
      |> Player.changeset(%{tutorial_step: 1})
      |> Ecto.Changeset.put_change(:guest_session_key, key)
      |> Repo.insert!(on_conflict: :nothing, conflict_target: :guest_session_key)

      player =
        from(p in Player, where: p.guest_session_key == ^key, lock: "FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload(:user)

      if is_nil(player.user_id) do
        case start.(player, scope(player)) do
          {:error, reason} -> Repo.rollback(reason)
          _ -> :ok
        end
      end

      player
    end)
  end

  def finalize(scope, %{phase: "finished", hero_ids: []} = record) do
    case __MODULE__.update(scope, record, & &1) do
      {:ok, record} -> record
      {:error, :stale} -> get!(scope, record.id)
      {:error, :invalid_snapshot} -> record
    end
  end

  def finalize(_, record), do: record

  def ranking(current_id, limit \\ 50) do
    visible_ranks =
      if current_id do
        dynamic([r, rank], rank.position <= ^limit or r.id == ^current_id)
      else
        dynamic([_r, rank], rank.position <= ^limit)
      end

    from(r in TrainingTeam,
      join: rank in subquery(ranked_runs()),
      on: rank.id == r.id,
      where: ^visible_ranks,
      order_by: rank.position,
      select: %{
        team: struct(r, [:id, :name, :player_id, :total_farm, :duration_seconds, :league_tier, :hero_ids]),
        position: rank.position
      },
      preload: [player: :user, heroes: :avatar]
    )
    |> Repo.all()
  end

  def best_ranks_for_players([]), do: %{}

  def best_ranks_for_players(player_ids) do
    from(rank in subquery(ranked_runs()),
      where: rank.player_id in ^player_ids,
      distinct: rank.player_id,
      order_by: rank.position,
      select: {rank.player_id, %{id: rank.id, position: rank.position}}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp ranked_runs do
    from(r in TrainingTeam,
      where: not is_nil(r.finished_at),
      windows: [ranking: [order_by: [desc: r.total_farm, asc: r.duration_seconds, asc: r.id]]],
      select: %{id: r.id, player_id: r.player_id, position: over(row_number(), :ranking)}
    )
  end

  def get!(scope, id), do: scope |> owned() |> Repo.get!(id)
  def get(scope, id), do: scope |> owned() |> Repo.get(id)

  def restore_pending(scope, record, %{phase: :engagement} = run) do
    case {TeamTraining.active_encounter(run), run[:resolution]} do
      {%{battles: [%Moba.Engine.Schema.Battle{} | _]} = encounter, %{duel: %{battle: %Moba.Engine.Schema.Battle{}}}} ->
        saved = encounter[:id] && get_encounter(scope, record.id, encounter.id)

        if saved && TrainingEncounters.ready?(saved, encounter),
          do: {:ok, record},
          else: __MODULE__.update(scope, record, & &1)

      _ ->
        {:error, :invalid_snapshot}
    end
  end

  def restore_pending(_, record, _), do: {:ok, record}

  def archive(scope, id) do
    with {:ok, id} <- Ecto.Type.cast(:id, id) do
      Repo.transaction(fn ->
        case scope |> owned() |> lock("FOR UPDATE") |> Repo.get(id) do
          nil ->
            Repo.rollback(:not_found)

          record ->
            record
            |> Ecto.Changeset.change(
              archived_at: DateTime.utc_now() |> DateTime.truncate(:second),
              lock_version: record.lock_version + 1
            )
            |> Repo.update!()
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def profile!(_scope, id) do
    team =
      from(r in TrainingTeam,
        where: r.phase == "finished" and not is_nil(r.finished_at),
        select:
          struct(r, [:id, :name, :player_id, :finished_at, :total_farm, :duration_seconds, :league_tier, :hero_ids]),
        preload: [player: :user, heroes: ^Game.Query.HeroQuery.load()]
      )
      |> Repo.get!(id)

    %{team | heroes: Enum.sort_by(team.heroes, &Enum.find_index(team.hero_ids, fn id -> id == &1.id end))}
  end

  def shard_buyback(scope, previous, hero_id \\ nil) do
    __MODULE__.update(scope, previous, fn run ->
      run = if hero_id, do: TeamTraining.select(run, hero_id), else: run

      if scope.user && TeamTraining.can_shard_buyback?(run) do
        user = Repo.one!(from u in Accounts.Schema.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE")
        price = Moba.shard_buyback_price(user.shard_count)

        if user.shard_count >= price do
          Accounts.update_user!(user, %{shard_count: user.shard_count - price})
          TeamTraining.shard_buyback(run)
        else
          run
        end
      else
        run
      end
    end)
  end

  def restart(scope, previous) do
    Repo.transaction(fn ->
      current = scope |> owned() |> lock("FOR UPDATE") |> Repo.get!(previous.id)
      if current.lock_version != previous.lock_version, do: Repo.rollback(:stale)
      run = state(current)

      if run.phase != :playing || !Enum.any?(TeamTraining.team(run), &TeamTraining.dead?/1),
        do: Repo.rollback(:unavailable)

      current
      |> Ecto.Changeset.change(Map.put(attributes(%{run | phase: :abandoned}), :lock_version, current.lock_version + 1))
      |> Repo.update!()

      %TrainingTeam{user_id: current.user_id, player_id: current.player_id}
      |> Ecto.Changeset.change(attributes(TeamTraining.restart(scope, run)))
      |> Repo.insert!()
    end)
  end

  def update(scope, %TrainingTeam{} = previous, fun) do
    Repo.transaction(fn ->
      current = scope |> owned() |> lock("FOR UPDATE") |> Repo.get(previous.id)
      if is_nil(current), do: Repo.rollback(:not_found)
      if current.lock_version != previous.lock_version, do: Repo.rollback(:stale)

      saved_run =
        case read_state(current) do
          {:ok, run} -> run
          {:error, reason} -> Repo.rollback(reason)
        end

      run =
        case fun.(saved_run) do
          {:error, error} -> Repo.rollback({:invalid, error})
          {:ok, run} -> run
          run -> run
        end

      encounters =
        Enum.map(run.encounters, fn encounter ->
          record =
            (encounter[:id] && Repo.get_by(TeamEncounter, id: encounter.id, team_run_id: current.id)) ||
              %TeamEncounter{team_run_id: current.id}

          record =
            record
            |> Ecto.Changeset.change(turn: encounter.turn, label: encounter.label)
            |> Repo.insert_or_update!()

          TrainingEncounters.persist!(record, encounter)
        end)

      run = %{run | encounters: encounters}

      current = settle(current, run)

      current
      |> Ecto.Changeset.change(Map.put(attributes(run), :lock_version, current.lock_version + 1))
      |> Repo.update!()
    end)
  end

  def encounters(scope, run_id) do
    from(e in TeamEncounter,
      join: r in subquery(owned(scope)),
      on: r.id == e.team_run_id,
      left_join: match in Game.Schema.Match,
      on: match.training_encounter_id == e.id,
      left_join: battle in Moba.Engine.Schema.Battle,
      on: battle.training_encounter_id == e.id and battle.training_index == 1,
      where: r.id == ^run_id,
      where: not is_nil(match.id) or not is_nil(battle.id),
      order_by: [asc: e.id]
    )
    |> Repo.all()
    |> Enum.flat_map(fn record ->
      case TrainingEncounters.replay(record) do
        {:ok, replay} ->
          [
            Map.merge(
              Map.take(record, [:id, :team_run_id, :turn, :label]),
              Map.take(replay, [:match_id, :battle_ids, :kind, :status, :recipient])
            )
          ]

        {:error, :invalid_snapshot} ->
          []
      end
    end)
  end

  def encounter!(scope, run_id, id) do
    scope
    |> encounter_query(run_id)
    |> Repo.get!(id)
    |> TrainingEncounters.load()
  end

  def get_encounter(scope, run_id, id) do
    scope |> encounter_query(run_id) |> Repo.get(id)
  end

  defp encounter_query(scope, run_id) do
    from(e in TeamEncounter, join: r in subquery(owned(scope)), on: r.id == e.team_run_id, where: r.id == ^run_id)
  end

  def read_state(%TrainingTeam{phase: phase, state: binary}) do
    with {:ok, run} <- Snapshot.read(binary),
         true <- valid_run?(run),
         true <- Atom.to_string(run.phase) == phase do
      {:ok, run}
    else
      _ -> {:error, :invalid_snapshot}
    end
  end

  defp valid_run?(%{phase: :draft, picks: picks, catalog: catalog, turn: turn}),
    do: is_list(picks) && is_map(catalog) && is_integer(turn)

  defp valid_run?(%{
         phase: phase,
         order: [_, _, _] = order,
         selected: selected,
         heroes: heroes,
         targets: targets,
         catalog: catalog,
         encounters: encounters,
         reward_mode: reward_mode,
         goal: goal,
         league_tier: league_tier,
         turns_left: turns_left,
         reserve_turns: reserve_turns,
         turn: turn
       })
       when phase in [:playing, :engagement, :finished, :abandoned] and reward_mode in [:shared, :focus] and
              is_map(heroes) and is_map(targets) and is_map(catalog) and is_list(encounters) and is_integer(goal) and
              is_integer(league_tier) and is_integer(turns_left) and is_integer(reserve_turns) and is_integer(turn) do
    selected in order && Enum.all?(order, &match?(%{hero: %Game.Schema.Hero{}}, heroes[&1]))
  end

  defp valid_run?(_), do: false

  def state(%TeamEncounter{state: nil} = record), do: record |> TrainingEncounters.load() |> state()

  def state(record) do
    Snapshot.decode(record.state)
  end

  defp attributes(run),
    do: %{name: Map.get(run, :name), state: Snapshot.encode(run), phase: to_string(run.phase), turn: run.turn}

  defp settle(%{hero_ids: []} = record, %{phase: :finished} = run) do
    player = Game.get_player!(record.player_id)
    finished = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      ~w(name level experience skill_levels_available gold total_gold_farm total_xp_farm wins losses buybacks total_hp total_mp atk speed armor power item_hp item_mp item_atk item_power item_armor item_speed skill_order item_order inventory_order pve_tier)a

    heroes =
      Enum.map(TeamTraining.team(run), fn unit ->
        h = unit.hero

        values =
          Map.take(h, attrs)
          |> Map.merge(%{
            name: TeamTraining.hero_name(h, record),
            league_tier: run.league_tier,
            pve_current_turns: 0,
            pve_total_turns: 0,
            pve_state: "alive",
            league_attempts: run.league_attempts,
            league_successes: run.league_successes
          })

        %Game.Schema.Hero{}
        |> Game.Schema.Hero.create_changeset(values, player, h.avatar, h.skills, h.items)
        |> Ecto.Changeset.change(training_team_id: record.id, inserted_at: run.started_at, finished_at: finished)
        |> Repo.insert!()
        |> Repo.preload([:player, :avatar])
      end)

    record =
      record
      |> Ecto.Changeset.change(
        phase: "finished",
        hero_ids: Enum.map(heroes, & &1.id),
        finished_at: finished,
        league_tier: run.league_tier,
        total_farm: Enum.sum(Enum.map(heroes, &(&1.total_gold_farm + &1.total_xp_farm))),
        duration_seconds: max(0, NaiveDateTime.diff(DateTime.to_naive(finished), run.started_at))
      )
      |> Repo.update!()

    Game.Quests.track_team_pve_progression!(record)
    Enum.each(heroes, &Game.Players.add_total_farm!(%{&1 | player: Game.get_player!(player.id)}))
    Game.update_hero_collection!(hd(heroes))
    record
  end

  defp settle(record, _), do: record

  defp owned(scope) do
    from r in TrainingTeam,
      join: p in subquery(players(scope)),
      on: p.id == r.player_id,
      where: is_nil(r.archived_at)
  end

  defp players(%{user: %{id: id}}), do: from(p in Player, where: p.user_id == ^id)
  defp players(%{user: nil, player_id: id}), do: from(p in Player, where: p.id == ^id and is_nil(p.user_id))
  defp players(_), do: from(p in Player, where: false)
end
