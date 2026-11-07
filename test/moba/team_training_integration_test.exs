defmodule Moba.TeamTrainingIntegrationTest do
  use Moba.DataCase, async: true
  import Test.TeamHelper
  alias Moba.{Game, Repo}
  alias Game.{TeamRuns, TeamTraining}

  test "a guest can persist a draft, claim it on registration and keep training" do
    scope = %{user: nil}
    pick = hd(team_picks(scope))
    player = TeamRuns.start_guest!("team-guest-#{System.unique_integer([:positive])}", pick)
    scope = TeamRuns.scope(player)
    {:ok, draft} = TeamRuns.draft(scope, player)
    assert length(TeamRuns.state(draft).picks) == 1
    assert draft.user_id == nil

    user = Test.AccountsHelper.create_user()
    Moba.after_registration(user, player.id)
    assert TeamRuns.get!(%{user: user}, draft.id).player_id == player.id
    assert_raise Ecto.NoResultsError, fn -> TeamRuns.get!(scope, draft.id) end
  end

  test "a completed TrainingTeam exports its three builds once, counts collection and progression, and never enters solo ranks" do
    {scope, player} = team_account(0)
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, &%{&1 | phase: :finished, league_tier: 4})
    assert length(record.hero_ids) == 3
    heroes = Game.get_heroes(record.hero_ids)
    assert Enum.all?(heroes, &(&1.training_team_id == record.id && &1.finished_at && &1.league_tier == 4))
    assert length(Game.Heroes.collection_for(player.id)) == 3
    assert length(Game.trained_pvp_heroes(player.id, [], 10)) == 3
    assert Game.get_player!(player.id).pve_tier == 1

    Game.rank_finished_heroes!()
    assert Enum.all?(Game.get_heroes(record.hero_ids), &is_nil(&1.pve_ranking))
    assert Enum.all?(heroes, &(Game.league_ranking(&1).position == nil))
    before = Repo.aggregate(Game.Schema.Hero, :count)
    {:ok, again} = TeamRuns.update(scope, record, & &1)
    assert again.hero_ids == record.hero_ids
    assert Repo.aggregate(Game.Schema.Hero, :count) == before
    assert TeamRuns.ranking(record.id) |> Enum.any?(&(&1.team.id == record.id))
  end

  test "a Novice team needs a Master finish to reach Adept" do
    {scope, player} = team_account(1)
    diamond = team_run(scope, player)
    {:ok, _} = TeamRuns.update(scope, diamond, &%{&1 | phase: :finished, league_tier: 4})
    assert Game.get_player!(player.id).pve_tier == 1

    master = team_run(scope, player)
    {:ok, _} = TeamRuns.update(scope, master, &%{&1 | phase: :finished, league_tier: Moba.master_league_tier()})
    assert Game.get_player!(player.id).pve_tier == 2
  end

  test "team standings sort total farm first, then elapsed time, regardless of league" do
    {scope, player} = team_account()
    first = team_run(scope, player)
    {:ok, first} = TeamRuns.update(scope, first, &%{&1 | phase: :finished})
    second = team_run(scope, player)
    {:ok, second} = TeamRuns.update(scope, second, &%{&1 | phase: :finished})
    first |> Ecto.Changeset.change(total_farm: 20000, duration_seconds: 120, league_tier: 2) |> Repo.update!()
    second |> Ecto.Changeset.change(total_farm: 20000, duration_seconds: 100, league_tier: 1) |> Repo.update!()
    ids = TeamRuns.ranking(first.id) |> Enum.map(& &1.team.id)
    assert Enum.find_index(ids, &(&1 == second.id)) < Enum.find_index(ids, &(&1 == first.id))
  end

  test "every team avatar receives all league-based progression credit from the completed run" do
    for league <- [2, 3, 4, 5, 6] do
      {scope, player} = team_account(0)
      record = team_run(scope, player)
      before = Game.get_player!(player.id).pve_progression
      Game.Quests.track_team_pve_progression!(record)
      assert Game.get_player!(player.id).pve_progression == before

      {:ok, record} = TeamRuns.update(scope, record, &%{&1 | phase: :finished, league_tier: league})
      codes = record.hero_ids |> Game.get_heroes() |> Enum.map(& &1.avatar.code) |> Enum.sort()
      progression = Game.get_player!(player.id).pve_progression || %Game.Schema.PveProgression{}

      for {field, required} <- [season_codes: 3, master_codes: 5, grandmaster_codes: 6] do
        assert Enum.sort(Map.fetch!(progression, field)) == if(league >= required, do: codes, else: [])
      end

      assert progression.invoker_codes == []
    end
  end

  test "perfect shared and focused teams credit all three avatars for Invoker and pay once" do
    for mode <- [:shared, :focus] do
      {scope, player} = team_account(6)
      record = team_run(scope, player)
      codes = TeamTraining.team(TeamRuns.state(record)) |> Enum.map(& &1.hero.avatar.code)

      previous =
        Game.list_avatars() |> Enum.map(& &1.code) |> Enum.uniq() |> Enum.reject(&(&1 in codes)) |> Enum.take(17)

      assert length(previous) == 17
      Game.update_player!(player, %{pve_progression: %{invoker_codes: previous}})
      before = Moba.Accounts.get_user!(scope.user.id).shard_count
      xp = if mode == :focus, do: [37_700, 22_300, 30_000], else: [30_000, 30_000, 30_000]
      record = finish_with_farm(scope, record, 6, xp, mode)
      assert record.total_farm == 180_000

      updated = Game.get_player!(player.id)
      assert updated.pve_tier == 7
      assert Enum.sort(updated.pve_progression.invoker_codes) == Enum.sort(previous ++ codes)
      assert updated.user.shard_count == before + Game.get_quest(7).prize

      for hero <- Game.get_heroes(record.hero_ids), do: Game.Quests.track_pve_progression!(hero)
      Game.Quests.track_team_pve_progression!(record)
      {:ok, again} = TeamRuns.update(scope, record, & &1)
      assert again.hero_ids == record.hero_ids
      assert Game.get_player!(player.id).user.shard_count == updated.user.shard_count
      assert Game.get_player!(player.id).pve_progression == updated.pve_progression
    end
  end

  test "an individually overfarmed carry cannot earn Invoker credit from an imperfect or lower-league team" do
    for {league, xp} <- [{6, [37_700, 22_299, 30_000]}, {5, [37_700, 22_300, 30_000]}] do
      {scope, player} = team_account(6)
      record = team_run(scope, player) |> then(&finish_with_farm(scope, &1, league, xp, :focus))
      [carry | _] = Game.get_heroes(record.hero_ids) |> Enum.sort_by(& &1.id)
      assert carry.total_xp_farm + carry.total_gold_farm > Moba.max_total_farm()
      for hero <- Game.get_heroes(record.hero_ids), do: Game.Quests.track_pve_progression!(hero)
      progression = Game.get_player!(player.id).pve_progression
      assert length(progression.season_codes) == 3
      assert length(progression.master_codes) == 3
      assert length(progression.grandmaster_codes) == if(league == 6, do: 3, else: 0)
      assert progression.invoker_codes == []
    end
  end

  test "a completed team can award Master, Grandmaster and Invoker together" do
    {scope, player} = team_account(4)
    record = team_run(scope, player)
    codes = TeamTraining.team(TeamRuns.state(record)) |> Enum.map(& &1.hero.avatar.code)
    previous = Game.list_avatars() |> Enum.map(& &1.code) |> Enum.uniq() |> Enum.reject(&(&1 in codes)) |> Enum.take(17)
    assert length(previous) == 17

    Game.update_player!(player, %{
      pve_progression: %{master_codes: previous, grandmaster_codes: previous, invoker_codes: previous}
    })

    before = Moba.Accounts.get_user!(scope.user.id).shard_count
    finish_with_farm(scope, record, 6, [37_700, 22_300, 30_000], :focus)
    updated = Game.get_player!(player.id)
    assert updated.pve_tier == 7
    assert Map.keys(updated.pve_progression.history) |> Enum.sort() == ["5", "6", "7"]
    prize = Enum.sum(Enum.map(5..7, &Game.get_quest(&1).prize))
    assert updated.user.shard_count == before + prize

    for field <- [:master_codes, :grandmaster_codes, :invoker_codes],
        do: assert(Enum.sort(Map.fetch!(updated.pve_progression, field)) == Enum.sort(previous ++ codes))
  end

  test "collected heroes retain their individual target wins and losses" do
    {scope, player} = team_account()
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = easy_target(run) |> then(&TeamTraining.battle(&1, hd(&1.targets[1]).id)) |> finish_team(scope)
        target = hd(run.targets[2])
        opponent = simple_unit(target.opponent, 5000, 10_000)
        run = put_in(run.heroes[2], simple_unit(run.heroes[2], 20, 1))
        target = %{target | opponent: opponent, defender: opponent.hero}
        run = put_in(run.targets[2], [target]) |> TeamTraining.select(2)
        run = TeamTraining.battle(run, target.id) |> finish_team(scope)
        %{run | phase: :finished}
      end)

    [winner, loser, unused] = Enum.map(record.hero_ids, &Game.get_hero!/1)
    assert {winner.wins, winner.losses} == {1, 0}
    assert {loser.wins, loser.losses} == {0, 1}
    assert {unused.wins, unused.losses} == {0, 0}
  end

  test "a beginner target loss persists its refunded turn and free recovery exactly once" do
    {scope, player} = team_account(0)
    record = team_run(scope, player)
    starting_gold = TeamRuns.state(record).heroes[1].hero.gold

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        unit = simple_unit(run.heroes[1], 20, 1)
        target = hd(run.targets[1])
        opponent = simple_unit(target.opponent, 5000, 10_000)
        target = %{target | opponent: opponent, defender: opponent.hero}
        run = run |> put_in([:heroes, 1], unit) |> put_in([:targets, 1], [target])
        TeamTraining.battle(run, target.id) |> finish_team(scope)
      end)

    run = record |> then(&TeamRuns.get!(scope, &1.id)) |> TeamRuns.state()
    assert run.turns_left == Moba.turns_per_tier()
    assert run.heroes[1].hero.losses == 1
    assert run.heroes[1].hero.gold == starting_gold
    assert run.heroes[1].hero.buybacks == 0
    refute TeamTraining.dead?(run.heroes[1])
    assert run.heroes[1].hp == Game.Training.Loadouts.max_hp(run.heroes[1])

    {:ok, unchanged} = TeamRuns.update(scope, record, & &1)
    assert TeamRuns.state(unchanged) == run
  end

  test "capped rewards persist exactly once and collected heroes retain redistributed farm" do
    {scope, player} = team_account()
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        unit = %{run.heroes[1] | auto_buy: false}
        run = put_in(run.heroes[1], Game.Training.Loadouts.grant_farm(unit, 29_900, 37_650, run.catalog))
        run = run |> easy_target(1, 2) |> TeamTraining.reward_mode(:focus)
        TeamTraining.battle(run, Enum.at(run.targets[1], 2).id)
      end)

    {:ok, record} = TeamRuns.update(scope, record, &finish_team(&1, scope))
    run = record |> then(&TeamRuns.get!(scope, &1.id)) |> TeamRuns.state()
    assert run.heroes[1].hero.level == 30
    assert run.heroes[1].hero.total_gold_farm == 30_000
    assert run.heroes[1].hero.total_xp_farm == 37_700
    assert run.heroes[2].hero.total_gold_farm == 850
    assert run.heroes[2].hero.total_xp_farm == 875
    assert run.heroes[3].hero.total_gold_farm == 850
    assert run.heroes[3].hero.total_xp_farm == 875

    encounter = hd(TeamRuns.encounters(scope, record.id))
    replay = TeamRuns.encounter!(scope, record.id, encounter.id) |> TeamRuns.state()
    assert replay.reward_totals == %{gold: 1800, xp: 1800}

    {:ok, unchanged} = TeamRuns.update(scope, record, &TeamTraining.battle_action(scope, &1, %{auto: true}))
    assert TeamRuns.state(unchanged) == run

    {:ok, completed} = TeamRuns.update(scope, unchanged, &%{&1 | phase: :finished})
    [carry, second, third] = Enum.map(completed.hero_ids, &Game.get_hero!/1)
    assert {carry.level, carry.total_gold_farm, carry.total_xp_farm} == {30, 30_000, 37_700}
    assert {second.total_gold_farm, second.total_xp_farm} == {850, 875}
    assert {third.total_gold_farm, third.total_xp_farm} == {850, 875}
    assert completed.total_farm == 71_150
  end

  defp finish_with_farm(scope, record, league, xp, mode) do
    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        heroes =
          run.order
          |> Enum.zip(xp)
          |> Map.new(fn {id, xp} ->
            unit = run.heroes[id]
            {id, Game.Training.Loadouts.grant_farm(%{unit | auto_buy: false}, 30_000, xp, run.catalog)}
          end)

        %{run | heroes: heroes, phase: :finished, league_tier: league, reward_mode: mode}
      end)

    record
  end
end
