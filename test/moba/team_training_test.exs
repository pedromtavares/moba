defmodule Moba.Game.TeamTrainingTest do
  use Moba.DataCase, async: true
  import Test.TeamHelper
  alias Moba.Game.{TeamRuns, TeamTraining}
  alias Moba.Game.Training.{Loadouts, Combat}

  setup tags do
    {scope, player} = team_account()

    if tags[:persisted] do
      record = team_run(scope, player)
      %{scope: scope, player: player, record: record, run: TeamRuns.state(record)}
    else
      %{scope: scope, player: player, run: team_state(scope, player)}
    end
  end

  test "team names survive a restart and cannot change once training starts", %{scope: scope, run: run} do
    named = Map.put(run, :name, "Night Watch")
    restarted = TeamTraining.restart(scope, named)
    assert restarted.name == "Night Watch"
    assert Enum.all?(TeamTraining.team(restarted), &(&1.hero.name == "Night Watch"))
    assert {:ok, ^named} = TeamTraining.name_team(scope, named, "New name")
    draft = %{named | phase: :draft}
    assert {:error, _} = TeamTraining.name_team(scope, draft, ["invalid"])
    assert {:ok, %{name: nil}} = TeamTraining.name_team(%{user: nil}, draft, "Ignored")
  end

  test "draft picks ignore individual names and new heroes inherit the team name", %{
    scope: scope,
    player: player,
    run: run
  } do
    draft = TeamTraining.draft(scope, player, run.catalog)
    [first | rest] = team_picks(scope)
    {:ok, draft} = TeamTraining.add_pick(scope, draft, Map.put(first, "name", "Ignored"))
    refute Map.has_key?(hd(draft.picks), :name)

    draft =
      Enum.reduce(rest, draft, fn pick, current ->
        {:ok, next} = TeamTraining.add_pick(scope, current, Map.delete(pick, "name"))
        next
      end)

    assert Enum.all?(TeamTraining.team(TeamTraining.begin_run(draft)), &(&1.hero.name == scope.user.username))
    {:ok, draft} = TeamTraining.name_team(scope, draft, String.duplicate("a", 30))
    assert Enum.all?(TeamTraining.team(TeamTraining.begin_run(draft)), &(&1.hero.name == String.duplicate("a", 30)))
  end

  @tag :persisted
  test "Shard buyback checks current balance, training eligibility, and phase before spending", %{
    scope: scope,
    record: record
  } do
    Moba.Accounts.update_user!(scope.user, %{shard_count: 100})

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        h = run.heroes[1]
        put_in(run.heroes[1], %{h | hp: 0, hero: %{h.hero | pve_state: "dead"}})
      end)

    {:ok, record} = TeamRuns.shard_buyback(scope, record)
    assert TeamTraining.dead?(TeamRuns.state(record).heroes[1])
    assert Moba.Accounts.get_user!(scope.user.id).shard_count == 100

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        put_in(run.heroes[1].hero.pve_tier, 4)
      end)

    scope.user.id |> Moba.Accounts.get_user!() |> Moba.Accounts.update_user!(%{shard_count: 0})
    {:ok, record} = TeamRuns.shard_buyback(scope, record)
    assert TeamTraining.dead?(TeamRuns.state(record).heroes[1])
    assert Moba.Accounts.get_user!(scope.user.id).shard_count == 0
    run = TeamRuns.state(record)
    refute TeamTraining.can_shard_buyback?(%{run | phase: :engagement})
    refute TeamTraining.can_shard_buyback?(put_in(run.heroes[1].hero.league_tier, Moba.master_league_tier()))
    assert TeamTraining.can_shard_buyback?(run)
  end

  test "three picks start one independent roster without replacing normal training", %{
    scope: scope,
    player: player,
    run: run
  } do
    assert run.phase == :playing
    assert length(TeamTraining.team(run)) == 3
    assert Enum.all?(TeamTraining.team(run), &(&1.auto_buy && length(&1.inventory) == 1))
    assert Game.get_player!(player.id).current_pve_hero_id == player.current_pve_hero_id
    assert TeamTraining.begin_run(%{run | phase: :draft, picks: Enum.take(run.picks, 2)}).phase == :draft
    assert {:error, _} = TeamTraining.add_pick(scope, run, hd(team_picks(scope)))
  end

  test "new team runs use solo starting gold before automatic purchases", %{run: run} do
    for tier <- 0..Moba.max_pve_tier() do
      started = %{run | phase: :draft, pve_tier: tier} |> TeamTraining.begin_run()

      for unit <- TeamTraining.team(started) do
        spent = Enum.sum(Enum.map(unit.inventory, &Game.item_price(&1.item)))
        assert unit.hero.gold + spent == Moba.initial_gold(%{pve_tier: tier})
        assert unit.hero.total_gold_farm == 0

        assert unit.hero.gold + spent >= 1200
        assert length(unit.inventory) == 1
        assert length(started.targets[unit.id]) == 3
      end
    end
  end

  test "every roster hero gets three targets with progression-appropriate difficulties", %{scope: scope, run: run} do
    for {tier, expected} <- [
          {0, ~w(moderate weak weak)},
          {1, ~w(moderate moderate weak)},
          {2, ~w(moderate moderate strong)},
          {3, ~w(moderate strong strong)},
          {4, ~w(strong strong strong)}
        ] do
      run = %{run | phase: :draft, pve_tier: tier} |> TeamTraining.begin_run()
      for id <- 1..3, do: assert(Enum.sort(Enum.map(run.targets[id], & &1.difficulty)) == expected)
    end

    assert TeamTraining.battle(run, hd(run.targets[2]).id) == run
    assert TeamTraining.select(run, 99) == run
    assert scope.user.is_admin
  end

  test "team targets use the normal training initiative roll, including boots and beginner protection", %{run: run} do
    for {speed, item_speed, tier, owner} <- [
          {0, 0, 2, :dire},
          {100, 0, 2, :radiant},
          {50, 50, 2, :radiant},
          {0, 0, 0, :radiant}
        ] do
      hero = %{run.heroes[1].hero | speed: speed, item_speed: item_speed, pve_tier: tier}
      candidate = put_in(run.heroes[1].hero, hero)
      pending = TeamTraining.battle(candidate, hd(candidate.targets[1]).id)
      encounter = TeamTraining.active_encounter(pending)
      expected = if owner == :radiant, do: 1, else: hd(encounter.dire).id
      assert encounter.initiator == owner
      assert encounter.duel.battle.initiator_id == expected
      assert Moba.Game.Training.Combat.next_turn(encounter.duel).attacker.hero_id == expected
    end
  end

  test "fractional initiative uses the shared solo roll and stores RNG after that roll", %{run: run} do
    run = put_in(run.heroes[1].hero, %{run.heroes[1].hero | speed: 40, item_speed: 10, pve_tier: 2})
    target = hd(run.targets[1])

    for seed <- 1..20 do
      battle = %Moba.Engine.Schema.Battle{
        attacker: run.heroes[1].hero,
        defender: target.defender,
        attacker_player: run.heroes[1].hero.player,
        defender_player: target.defender.player
      }

      :rand.seed(:exsss, {seed, 123, 456})
      expected = Moba.Engine.Core.determine_initiator(battle)
      expected_rng = :rand.export_seed()
      :rand.seed(:exsss, {seed, 123, 456})
      duel = TeamTraining.battle(run, target.id) |> TeamTraining.active_encounter() |> Map.fetch!(:duel)
      assert duel.battle.initiator_id == expected.initiator.id
      assert duel.rng == expected_rng
    end
  end

  test "shared rewards credit both currencies and refresh targets for the entire roster", %{
    scope: scope,
    run: run
  } do
    run = easy_target(run, 1, 2)
    target = Enum.at(run.targets[1], 2)
    pending = TeamTraining.battle(run, target.id)
    assert pending.phase == :engagement
    assert pending.turns_left == 4
    assert TeamTraining.select(pending, 2) == pending
    assert TeamTraining.reward_mode(pending, :focus) == pending
    finished = finish_team(pending, scope)
    assert finished.phase == :playing

    for h <- TeamTraining.team(finished) do
      assert h.hero.total_gold_farm == div(target.reward, 3)
      assert h.hero.total_xp_farm == div(target.reward, 3)
      assert h.hp == Loadouts.max_hp(h)
      assert h.energy == Loadouts.max_energy(h)
    end

    for id <- run.order do
      previous_ids = Enum.map(run.targets[id], & &1.id)
      refute Enum.any?(finished.targets[id], &(&1.id in previous_ids))
      assert length(finished.targets[id]) == length(run.targets[id])
    end

    assert finished.heroes[2].hero.level > run.heroes[2].hero.level
  end

  test "focus gives the same entire gold and XP pool to the selected fighter", %{scope: scope, run: run} do
    run = easy_target(run, 2) |> TeamTraining.reward_mode(:focus)
    target = hd(run.targets[2])
    finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
    assert finished.heroes[2].hero.total_gold_farm == target.reward
    assert finished.heroes[2].hero.total_xp_farm == target.reward
    refute Enum.any?(finished.targets[2], &(&1.id == target.id))

    for id <- [1, 3] do
      assert finished.heroes[id].hero.total_gold_farm == 0
      assert finished.heroes[id].hero.total_xp_farm == 0
      refute finished.targets[id] == run.targets[id]
    end
  end

  test "refreshed focused targets follow each hero's own farm rather than the selected carry", %{scope: scope, run: run} do
    run =
      run
      |> easy_target(1)
      |> TeamTraining.reward_mode(:focus)
      |> update_in([:heroes, 2], &Loadouts.grant_farm(&1, 6000, 6000, run.catalog))
      |> update_in([:heroes, 3], &Loadouts.grant_farm(&1, 18_000, 18_000, run.catalog))

    finished = TeamTraining.battle(run, hd(run.targets[1]).id) |> finish_team(scope)

    farms =
      Map.new(run.order, fn id ->
        values =
          finished.targets[id]
          |> Enum.filter(&(&1.difficulty == "moderate"))
          |> Enum.map(&(&1.defender.total_gold_farm + &1.defender.total_xp_farm))

        {id, values}
      end)

    assert Enum.min(farms[3]) > Enum.max(farms[2])
    assert Enum.min(farms[2]) > Enum.max(farms[1])

    for id <- run.order do
      previous_ids = Enum.map(run.targets[id], & &1.id)
      refute Enum.any?(finished.targets[id], &(&1.id in previous_ids))
    end
  end

  test "a focused reward fills level 30 and 30K gold exactly and splits each overflow", %{scope: scope, run: run} do
    run = run |> grant(1, 29_900, 37_650) |> easy_target(1, 2) |> TeamTraining.reward_mode(:focus)
    target = Enum.at(run.targets[1], 2)
    assert target.reward == 1800
    finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
    hero = finished.heroes[1].hero
    assert hero.level == 30
    assert hero.experience == 0
    assert hero.total_xp_farm == 37_700
    assert hero.total_gold_farm == 30_000

    for id <- [2, 3] do
      assert finished.heroes[id].hero.total_gold_farm == 850
      assert finished.heroes[id].hero.total_xp_farm == 875
    end

    assert finished.last_result.rewards == [
             {1, %{gold: 100, xp: 50}},
             {2, %{gold: 850, xp: 875}},
             {3, %{gold: 850, xp: 875}}
           ]

    assert hd(finished.encounters).reward_totals == %{gold: 1800, xp: 1800}
  end

  test "gold and XP overflow independently as soon as their own cap is reached", %{scope: scope, run: run} do
    for {gold, xp} <- [{30_000, 0}, {0, 37_699}, {30_000, 37_699}] do
      run = run |> grant(1, gold, xp) |> easy_target(1, 2) |> TeamTraining.reward_mode(:focus)
      target = Enum.at(run.targets[1], 2)
      finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
      assert finished.heroes[1].hero.total_gold_farm == min(30_000, gold + target.reward)
      assert finished.heroes[1].hero.total_xp_farm == min(37_700, xp + target.reward)
      assert finished.heroes[1].hero.level <= 30

      for id <- [2, 3] do
        assert finished.heroes[id].hero.total_gold_farm == if(gold == 30_000, do: 900, else: 0)
        assert finished.heroes[id].hero.total_xp_farm == if(xp == 37_699, do: if(id == 2, do: 900, else: 899), else: 0)
      end

      assert Enum.sum(Enum.map(TeamTraining.team(finished), & &1.hero.total_gold_farm)) == gold + target.reward
      assert Enum.sum(Enum.map(TeamTraining.team(finished), & &1.hero.total_xp_farm)) == xp + target.reward
    end
  end

  test "overflow cascades past a nearly capped teammate without losing odd reward amounts", %{scope: scope, run: run} do
    run =
      run |> grant(1, 30_000, 37_699) |> grant(2, 29_990, 37_695) |> easy_target() |> TeamTraining.reward_mode(:focus)

    target = hd(run.targets[1])
    run = put_in(run.targets[1], [%{target | reward: 1801} | tl(run.targets[1])])
    finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
    assert finished.heroes[2].hero.total_gold_farm == 30_000
    assert finished.heroes[2].hero.total_xp_farm == 37_700
    assert finished.heroes[2].hero.level == 30
    assert finished.heroes[3].hero.total_gold_farm == 1791
    assert finished.heroes[3].hero.total_xp_farm == 1795

    assert finished.last_result.rewards == [
             {1, %{gold: 0, xp: 1}},
             {2, %{gold: 10, xp: 5}},
             {3, %{gold: 1791, xp: 1795}}
           ]

    assert hd(finished.encounters).reward_totals == %{gold: 1801, xp: 1801}
  end

  test "spending gold does not reopen the earned-gold cap", %{scope: scope, run: run} do
    run =
      run
      |> grant(1, 30_000, 0)
      |> then(&TeamTraining.configure(scope, &1, :buy, "blades_of_attack"))
      |> easy_target(1, 2)
      |> TeamTraining.reward_mode(:focus)

    gold_before = run.heroes[1].hero.gold
    target = Enum.at(run.targets[1], 2)
    finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
    assert finished.heroes[1].hero.total_gold_farm == 30_000
    assert finished.heroes[1].hero.gold == gold_before
    assert finished.heroes[1].hero.total_xp_farm == target.reward

    for id <- [2, 3] do
      assert finished.heroes[id].hero.total_gold_farm == div(target.reward, 2)
      assert finished.heroes[id].hero.total_xp_farm == 0
    end
  end

  test "shared battles, leagues and bosses redistribute capped shares without exceeding either cap", %{
    scope: scope,
    run: run
  } do
    for kind <- [:farm, :league, :boss] do
      run = run |> grant(1, 30_000, 37_700) |> grant(2, 29_900, 37_600)

      pending =
        if kind == :farm do
          run = easy_target(run, 3)
          TeamTraining.battle(run, hd(run.targets[3]).id)
        else
          heroes = Map.new(run.heroes, fn {id, h} -> {id, %{h | hero: %{h.hero | skill_levels_available: 0}}} end)

          %{run | heroes: heroes, turns_left: 0, league_tier: if(kind == :boss, do: 5, else: 0), goal: 6}
          |> TeamTraining.league()
          |> simple_league()
        end

      reward = TeamTraining.active_encounter(pending).reward
      finished = finish_team(pending, scope)
      assert finished.heroes[1].hero.total_gold_farm == 30_000
      assert finished.heroes[1].hero.total_xp_farm == 37_700
      assert finished.heroes[2].hero.total_gold_farm == 30_000
      assert finished.heroes[2].hero.total_xp_farm == 37_700
      assert finished.heroes[3].hero.total_gold_farm == reward - 100
      assert finished.heroes[3].hero.total_xp_farm == reward - 100
      assert hd(finished.encounters).reward_totals == %{gold: reward, xp: reward}
    end
  end

  test "a fully capped roster gains no extra farm or levels", %{scope: scope, run: run} do
    run =
      Enum.reduce(run.order, run, fn id, acc ->
        acc = grant(acc, id, 30_000, 37_700)
        put_in(acc.heroes[id].hero.skill_levels_available, 0)
      end)

    finished = run |> TeamTraining.league() |> simple_league() |> finish_team(scope)

    for unit <- TeamTraining.team(finished) do
      assert unit.hero.total_gold_farm == 30_000
      assert unit.hero.total_xp_farm == 37_700
      assert unit.hero.level == 30
      assert unit.hero.experience == 0
    end

    assert finished.last_result.rewards == []
    assert hd(finished.encounters).reward_totals == %{gold: 0, xp: 0}
  end

  test "target, league and boss spoils are triple solo rewards and shared only once", %{scope: scope, run: run} do
    for difficulty <- ~w(weak moderate strong), tier <- 0..5, difficulty != "weak" || tier < 2 do
      assert TeamTraining.farm_reward(difficulty, tier) == 3 * Moba.pve_battle_rewards(difficulty, tier)
    end

    for {tier, goal, bonus} <- [{0, run.goal, Moba.league_win_bonus()}, {5, 6, Moba.boss_win_bonus()}] do
      pending = %{run | turns_left: 0, league_tier: tier, goal: goal} |> TeamTraining.league() |> simple_league()
      assert TeamTraining.active_encounter(pending).reward == 3 * bonus
      finished = finish_team(pending, scope)

      for h <- TeamTraining.team(finished) do
        assert h.hero.total_gold_farm == bonus
        assert h.hero.total_xp_farm == bonus
      end

      for id <- run.order do
        previous_ids = Enum.map(run.targets[id], & &1.id)
        refute Enum.any?(finished.targets[id], &(&1.id in previous_ids))
      end
    end
  end

  test "league and boss rewards stay equally shared when target rewards are focused", %{scope: scope, run: run} do
    for tier <- [0, Moba.master_league_tier()] do
      pending =
        %{run | turns_left: 0, league_tier: tier, goal: 6}
        |> TeamTraining.reward_mode(:focus)
        |> TeamTraining.select(2)
        |> TeamTraining.league()
        |> simple_league()

      encounter = TeamTraining.active_encounter(pending)
      assert encounter.reward_mode == :shared

      # A pending encounter saved before this rule was enforced must also split its bounty.
      pending = put_in(pending.encounters, [%{encounter | reward_mode: :focus}])
      finished = finish_team(pending, scope)
      assert finished.last_result.mode == :shared
      assert hd(finished.encounters).reward_mode == :shared
      assert finished.reward_mode == :focus

      for h <- TeamTraining.team(finished) do
        assert h.hero.total_gold_farm == div(encounter.reward, 3)
        assert h.hero.total_xp_farm == div(encounter.reward, 3)
      end
    end
  end

  test "team leveling matches solo stat growth and skill points across multiple level gains", %{
    player: player,
    run: run
  } do
    unit = run.heroes[1]
    solo = Game.Heroes.create!(%{name: "Solo parity"}, player, unit.hero.avatar, unit.hero.skills)
    fields = ~w(level experience total_hp total_mp atk skill_levels_available total_xp_farm)a

    Enum.reduce([600, 1300, 5000, 28000], {unit, solo}, fn xp, {unit, solo} ->
      unit = Loadouts.grant_farm(unit, 0, xp, run.catalog)
      solo = Game.Heroes.update_attacker!(solo, %{total_xp: xp})
      assert Map.take(unit.hero, fields) == Map.take(solo, fields)
      {unit, solo}
    end)
  end

  test "a single 1800 gold and XP pool gives 600 each when shared or 1800 to the focus hero", %{scope: scope, run: run} do
    run = easy_target(run, 1, 2)
    target = Enum.at(run.targets[1], 2)
    assert target.reward == 1800
    shared = TeamTraining.battle(run, target.id) |> finish_team(scope)
    focused = run |> TeamTraining.reward_mode(:focus) |> TeamTraining.battle(target.id) |> finish_team(scope)

    for finished <- [shared, focused] do
      assert Enum.sum(Enum.map(TeamTraining.team(finished), & &1.hero.total_gold_farm)) == 1800
      assert Enum.sum(Enum.map(TeamTraining.team(finished), & &1.hero.total_xp_farm)) == 1800
    end

    for h <- TeamTraining.team(shared) do
      assert h.hero.total_gold_farm == 600
      assert h.hero.total_xp_farm == 600
    end

    assert focused.heroes[1].hero.total_gold_farm == 1800
    assert focused.heroes[1].hero.total_xp_farm == 1800

    for id <- [2, 3] do
      assert focused.heroes[id].hero.total_gold_farm == 0
      assert focused.heroes[id].hero.total_xp_farm == 0
    end
  end

  test "league rosters use the final solo opponents in battle order", %{run: run} do
    for {tier, expected} <- [
          {0, [{3, "moderate"}, {4, "moderate"}, {5, "moderate"}]},
          {1, [{7, "moderate"}, {8, "moderate"}, {8, "moderate"}]},
          {2, [{11, "moderate"}, {11, "moderate"}, {12, "moderate"}]},
          {3, [{15, "moderate"}, {16, "moderate"}, {16, "strong"}]},
          {4, [{19, "moderate"}, {20, "moderate"}, {20, "strong"}]}
        ] do
      pending = TeamTraining.league(%{run | turns_left: 0, league_tier: tier, goal: 5})
      encounter = TeamTraining.active_encounter(pending)
      assert Enum.map(encounter.dire, &{&1.hero.level, &1.hero.bot_difficulty}) == expected
      assert encounter.duel.battle.defender.id == hd(encounter.dire).id
    end
  end

  test "a missing seeded opponent still fills the correct league slot", %{run: run} do
    Repo.update_all(
      from(h in Game.Schema.Hero, where: h.level == 16 and h.bot_difficulty == "strong"),
      set: [archived_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )

    pending = TeamTraining.league(%{run | turns_left: 0, league_tier: 3, goal: 5})
    assert [_, _, %{hero: %{level: 16, bot_difficulty: "strong"}}] = TeamTraining.active_encounter(pending).dire
  end

  test "league opponents scale with the midpoint of the roster's average and highest farm", %{run: run} do
    ready = %{run | turns_left: 0}

    for {farm, levels} <- [{[2600, 2600, 2600], [3, 4, 5]}, {[7800, 0, 0], [5, 6, 7]}] do
      scaled =
        Enum.zip(ready.order, farm)
        |> Enum.reduce(ready, fn {id, amount}, acc ->
          update_in(acc.heroes[id].hero, &%{&1 | total_gold_farm: amount, total_xp_farm: amount})
        end)

      encounter = scaled |> TeamTraining.league() |> TeamTraining.active_encounter()
      assert Enum.map(encounter.dire, & &1.hero.level) == levels
    end
  end

  test "a target loss refunds its turn and requires a non-beginner hero to buy back", %{scope: scope, run: run} do
    target = hd(run.targets[1])
    opponent = simple_unit(target.opponent, 5000, 10_000)
    run = put_in(run.heroes[1], simple_unit(run.heroes[1], 20, 1))
    run = put_in(run.targets[1], [%{target | opponent: opponent, defender: opponent.hero} | tl(run.targets[1])])
    finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
    assert finished.phase == :playing
    assert finished.turns_left == run.turns_left
    assert finished.heroes[1].deaths == 1
    assert finished.heroes[1].hp == 0
    assert finished.heroes[1].energy == 0
    assert finished.heroes[1].hero.pve_state == "dead"
    assert finished.heroes[1].hero.losses == 1
    assert finished.heroes[1].hero.wins == 0
    assert finished.heroes[1].hero.total_xp_farm == 0
    assert finished.last_result.winner == :dire
    for id <- run.order, do: refute(finished.targets[id] == run.targets[id])
    assert TeamTraining.battle(finished, hd(finished.targets[1]).id) == finished
    assert TeamTraining.league(%{finished | turns_left: 0}) == %{finished | turns_left: 0}

    surviving = finished |> TeamTraining.select(2) |> TeamTraining.battle(hd(finished.targets[2]).id)
    assert surviving.phase == :engagement
    assert TeamTraining.buyback(surviving) == surviving

    price = Game.buyback_price(finished.heroes[1].hero)
    revived = TeamTraining.buyback(finished)
    assert revived.heroes[1].hero.pve_state == "alive"
    assert revived.heroes[1].hero.gold == finished.heroes[1].hero.gold - price
    assert revived.heroes[1].hero.total_gold_farm == finished.heroes[1].hero.total_gold_farm - price
    assert revived.heroes[1].hero.buybacks == 1
    assert revived.heroes[1].hp == Loadouts.max_hp(revived.heroes[1])
    assert revived.heroes[1].energy == Loadouts.max_energy(revived.heroes[1])
    assert revived.turns_left == finished.turns_left
    assert revived.targets == finished.targets
    assert TeamTraining.buyback(revived) == revived
    assert TeamTraining.battle(revived, hd(revived.targets[1]).id).phase == :engagement
    broke = put_in(finished.heroes[1].hero.gold, price - 1)
    assert TeamTraining.buyback(broke) == broke
    assert TeamTraining.buyback(%{finished | phase: :finished}) == %{finished | phase: :finished}
  end

  test "target loss refunds and beginner protection match solo in either reward mode", %{scope: scope, run: run} do
    for tier <- [0, 2], mode <- [:shared, :focus] do
      run = %{run | pve_tier: tier, selected: 2, turns_left: 1, reward_mode: mode}
      unit = simple_unit(run.heroes[2], 20, 1)
      unit = %{unit | hero: %{unit.hero | pve_tier: tier}}
      target = hd(run.targets[2])
      opponent = simple_unit(target.opponent, 5000, 10_000)
      target = %{target | opponent: opponent, defender: opponent.hero}
      run = run |> put_in([:heroes, 2], unit) |> put_in([:targets, 2], [target])

      finished = TeamTraining.battle(run, target.id) |> finish_team(scope)
      assert finished.phase == :playing
      assert finished.turns_left == 1
      assert finished.reserve_turns == run.reserve_turns
      assert finished.heroes[2].hero.losses == 1
      assert finished.heroes[2].hero.buybacks == 0
      assert finished.last_result.rewards == []

      for id <- run.order do
        assert finished.heroes[id].hero.pve_current_turns == 1
        assert finished.heroes[id].hero.total_xp_farm == run.heroes[id].hero.total_xp_farm
        assert finished.heroes[id].hero.gold == run.heroes[id].hero.gold
        previous_ids = Enum.map(run.targets[id], & &1.id)
        refute Enum.any?(finished.targets[id], &(&1.id in previous_ids))
      end

      if tier == 0 do
        refute TeamTraining.dead?(finished.heroes[2])
        assert finished.heroes[2].hp == Loadouts.max_hp(finished.heroes[2])
        assert finished.heroes[2].energy == Loadouts.max_energy(finished.heroes[2])
        assert TeamTraining.battle(finished, hd(finished.targets[2]).id).phase == :engagement
      else
        assert TeamTraining.dead?(finished.heroes[2])
        assert finished.heroes[2].hp == 0
      end
    end
  end

  test "team league bonuses match solo for every beginner tier and leave enemy stats unbuffed", %{run: run} do
    fields = ~w(total_hp total_mp atk power armor speed base_atk base_power base_armor)a

    for tier <- 0..4, league <- [0, 3] do
      heroes =
        Map.new(run.heroes, fn {id, unit} ->
          {id, %{unit | hero: %{unit.hero | pve_tier: tier}}}
        end)

      pending =
        %{run | heroes: heroes, pve_tier: tier, league_tier: league, goal: 6, turns_left: 0}
        |> TeamTraining.league()

      encounter = TeamTraining.active_encounter(pending)
      assert encounter.duel.battle.type == "league"
      assert encounter.initiator == :radiant
      turn = Combat.next_turn(encounter.duel)
      solo = Moba.Engine.Core.Turns.build_turn(encounter.duel.battle, %{})
      assert Map.take(turn.attacker, fields) == Map.take(solo.attacker, fields)
      assert turn.attacker.current_hp == solo.attacker.total_hp
      assert turn.attacker.current_mp == solo.attacker.total_mp

      enemy = hd(encounter.dire)
      assert turn.defender.total_hp == Loadouts.max_hp(enemy)
      assert turn.defender.atk == enemy.hero.atk + enemy.hero.item_atk
      assert Enum.all?(encounter.dire, &(&1.hero.bot_difficulty != nil))

      for unit <- encounter.radiant do
        original = run.heroes[unit.id].hero
        assert unit.hero.total_hp == original.total_hp
        assert unit.hero.atk == original.atk

        assert unit.hp ==
                 original.total_hp + original.item_hp +
                   round(Moba.league_buff_multiplier(tier, league) * (original.total_hp + original.item_hp))
      end
    end
  end

  test "league fallbacks are bots and cannot receive the player's beginner bonus", %{run: run} do
    heroes =
      Map.new(run.heroes, fn {id, unit} ->
        {id, %{unit | hero: %{unit.hero | total_gold_farm: 1_000_000, total_xp_farm: 1_000_000}}}
      end)

    encounter =
      %{run | heroes: heroes, turns_left: 0} |> TeamTraining.league() |> TeamTraining.active_encounter()

    assert Enum.all?(encounter.dire, &(&1.hero.bot_difficulty == "moderate"))
    turn = Combat.next_turn(encounter.duel)
    enemy = hd(encounter.dire)
    assert turn.defender.total_hp == Loadouts.max_hp(enemy)
    assert turn.defender.atk == enemy.hero.atk + enemy.hero.item_atk
  end

  test "buffed league pairings keep survivor-first and carry exact remaining resources", %{scope: scope, run: run} do
    for survivor <- [:radiant, :dire] do
      heroes =
        Map.new(run.heroes, fn {id, unit} ->
          hp = if id == 1 && survivor == :dire, do: 1, else: 1000
          atk = if id == 1 && survivor == :dire, do: 1, else: 60
          unit = simple_unit(unit, hp, atk)
          unit = %{unit | hero: %{unit.hero | speed: if(id == 1, do: 0, else: 100)}}
          {id, unit}
        end)

      pending = %{run | heroes: heroes, turns_left: 0} |> TeamTraining.league()
      encounter = TeamTraining.active_encounter(pending)

      units =
        Map.new(encounter.units, fn {id, unit} ->
          {id, if(unit.side == :dire, do: simple_unit(unit, 100, 10), else: unit)}
        end)

      enemy_id = hd(encounter.remaining.dire)
      duel = Combat.new_duel(units[1], units[enemy_id], type: "league")

      encounter = %{
        encounter
        | units: units,
          dire: Enum.map(encounter.dire, &units[&1.id]),
          duel: duel,
          battles: [duel.battle]
      }

      pending = %{pending | encounters: [encounter], resolution: %{duel: duel}}

      next =
        Enum.reduce_while(1..100, pending, fn _, current ->
          if length(hd(current.encounters).battles) == 2,
            do: {:halt, current},
            else: {:cont, TeamTraining.battle_action(scope, current, %{auto: true})}
        end)

      encounter = TeamTraining.active_encounter(next)
      [first, second] = encounter.battles
      last_turn = List.last(first.turns)
      survivor_id = if survivor == :radiant, do: 1, else: enemy_id
      retained = Enum.find([last_turn.attacker, last_turn.defender], &(&1.hero_id == survivor_id))
      assert second.type == "league"
      assert second.initiator_id == survivor_id
      prepared = Combat.next_turn(encounter.duel)
      assert prepared.attacker.hero_id == survivor_id
      assert prepared.attacker.current_hp == retained.current_hp
      assert prepared.attacker.current_mp == retained.current_mp
      assert retained.current_hp < retained.total_hp

      if survivor == :dire do
        assert prepared.defender.hero_id == 2
        assert prepared.defender.current_hp == prepared.defender.total_hp
        assert prepared.defender.current_mp == prepared.defender.total_mp
      end

      finished = finish_team(next, scope)
      assert finished.last_result.winner == :radiant

      for unit <- TeamTraining.team(finished) do
        assert unit.hp == Loadouts.max_hp(unit)
        assert unit.energy == Loadouts.max_energy(unit)
      end
    end
  end

  test "a league victory revives all fallen heroes for free in either reward mode", %{scope: scope, run: run} do
    for mode <- [:shared, :focus] do
      pending =
        %{run | turns_left: 0} |> TeamTraining.reward_mode(mode) |> TeamTraining.league() |> league_with_casualty()

      after_first =
        Enum.reduce_while(1..100, pending, fn _, current ->
          if length(hd(current.encounters).battles) == 2,
            do: {:halt, current},
            else: {:cont, TeamTraining.battle_action(scope, current, %{auto: true})}
        end)

      assert after_first.phase == :engagement
      assert hd(after_first.encounters).units[1].hp == 0
      finished = finish_team(after_first, scope)
      assert hd(finished.encounters).winner == :radiant
      assert finished.league_tier == 1
      assert finished.heroes[1].deaths == 1
      assert hd(finished.encounters).units[1].hp == 0

      for h <- TeamTraining.team(finished) do
        refute TeamTraining.dead?(h)
        assert h.hp == Loadouts.max_hp(h)
        assert h.energy == Loadouts.max_energy(h)
        assert h.hero.buybacks == 0
      end

      assert TeamTraining.buyback(finished) == finished
      assert TeamTraining.battle(finished, hd(finished.targets[1]).id).phase == :engagement
    end
  end

  test "losing the league still requires buybacks for its fallen heroes", %{scope: scope, run: run} do
    pending = %{run | turns_left: 0} |> TeamTraining.league() |> simple_league()
    e = TeamTraining.active_encounter(pending)
    units = Map.new(e.units, fn {id, h} -> {id, if(id in run.order, do: simple_unit(h, 1, 1), else: h)} end)
    duel = Combat.new_duel(units[1], units[hd(e.remaining.dire)])
    e = %{e | units: units, radiant: Enum.map(e.radiant, &units[&1.id]), duel: duel, battles: [duel.battle]}
    finished = finish_team(%{pending | encounters: [e], resolution: %{duel: duel}}, scope)
    assert hd(finished.encounters).winner == :dire
    assert finished.league_tier == 0
    for h <- TeamTraining.team(finished), do: assert(TeamTraining.dead?(h))
    assert TeamTraining.battle(finished, hd(finished.targets[1]).id) == finished
  end

  test "league challenges are sequential 3v3 with preserved resources between fighters", %{scope: scope, run: run} do
    pending = %{run | turns_left: 0} |> TeamTraining.league() |> simple_league()
    assert length(hd(pending.encounters).radiant) == 3
    assert length(hd(pending.encounters).dire) == 3

    after_first =
      Enum.reduce_while(1..100, pending, fn _, current ->
        if length(hd(current.encounters).battles) == 2,
          do: {:halt, current},
          else: {:cont, TeamTraining.battle_action(scope, current, %{auto: true})}
      end)

    assert after_first.phase == :engagement
    assert length(after_first.encounters) == 1
    assert after_first.league_tier == 0
    assert after_first.turns_left == 0
    assert Enum.all?(TeamTraining.team(after_first), &(&1.hero.total_gold_farm == 0 && &1.hero.total_xp_farm == 0))
    finished = finish_team(after_first, scope)
    e = hd(finished.encounters)
    assert finished.league_tier == 1
    assert finished.turns_left == 5
    assert finished.reserve_turns == run.reserve_turns - 5
    assert length(e.battles) == 3
    [first, second | _] = e.battles
    previous = List.last(first.turns)
    retained = if previous.attacker.hero_id == 1, do: previous.attacker.current_hp, else: previous.defender.current_hp
    assert hd(second.turns).attacker.starting_hp == retained
    assert retained < 5000
    assert Enum.all?(TeamTraining.team(finished), &(&1.hp == Loadouts.max_hp(&1)))
  end

  test "unspent points on any teammate block league and final challenges", %{run: run} do
    for {tier, goal} <- [{0, run.goal}, {5, 6}], id <- run.order do
      ready = %{run | turns_left: 0, league_tier: tier, goal: goal}
      blocked = put_in(ready.heroes[id].hero.skill_levels_available, 1)
      assert Enum.map(TeamTraining.pending_skill_heroes(blocked), & &1.id) == [id]
      assert TeamTraining.league(blocked) == blocked
      assert TeamTraining.league(ready).phase == :engagement
    end
  end

  test "turns gate league entry and Roshan is the final 3v1 encounter", %{run: run} do
    assert TeamTraining.league(run) == run
    maxed = Enum.reduce(run.order, run, fn id, acc -> put_in(acc.heroes[id].hero.level, 30) end)
    pending = %{maxed | league_tier: 5, goal: 6} |> TeamTraining.league()
    e = TeamTraining.active_encounter(pending)
    assert e.kind == :boss
    assert length(e.radiant) == 3
    assert [boss] = e.dire
    assert boss.hero.name == "Roshan"
    assert boss.hero.items == []
    assert boss.hp == 10_000
    assert Loadouts.max_hp(boss) == 10_000
    assert e.duel.battle.defender.total_hp == 10_000
    assert Enum.count(boss.hero.skills, &(&1.code == "boss_ult" && &1.ultimate)) == 1
    assert Enum.any?(e.duel.battle.defender.skills, &(&1.code == "boss_ult"))

    ultimate = Enum.find(boss.hero.skills, & &1.ultimate)
    duel = Combat.new_duel(boss, hd(e.radiant), type: "league") |> Combat.step(%{auto: true})
    turn = hd(duel.battle.turns)
    assert turn.attacker.battle_armor == ultimate.armor_amount
    assert turn.attacker.battle_power == ultimate.power_amount
  end

  test "Roshan's first fight rolls the player's Speed including item bonuses", %{run: run} do
    for {speed, item_speed, expected} <- [{0, 0, 3000}, {100, 0, 1}, {50, 50, 1}] do
      ready = %{run | turns_left: 0, league_tier: 5, goal: 6}
      hero = %{ready.heroes[1].hero | speed: speed, item_speed: item_speed, pve_tier: 2}
      pending = ready |> put_in([:heroes, 1, :hero], hero) |> TeamTraining.league()
      encounter = TeamTraining.active_encounter(pending)
      assert encounter.duel.battle.initiator_id == expected
      assert Combat.next_turn(encounter.duel).attacker.hero_id == expected
    end
  end

  test "each incoming hero gets a fresh 90-Speed roll against surviving Roshan", %{run: run, scope: scope} do
    heroes =
      Map.new(run.heroes, fn {id, unit} ->
        unit = simple_unit(unit, 1, 1)
        {id, %{unit | hero: %{unit.hero | speed: 90, item_speed: 0, pve_tier: 2}}}
      end)

    ready = %{run | heroes: heroes, turns_left: 0, league_tier: 5, goal: 6}

    for seed <- 1..10 do
      boss = TeamTraining.boss_preview(ready) |> simple_unit(10_000, 1000)
      seeded = %{ready | boss: boss}
      :rand.seed(:exsss, {seed, 123, 456})
      expected = if Enum.random(1..100) <= 90, do: 1, else: boss.id
      :rand.seed(:exsss, {seed, 123, 456})
      pending = TeamTraining.league(seeded)
      assert pending.resolution.duel.battle.initiator_id == expected

      Enum.reduce(2..3, pending, fn id, current ->
        before_death =
          Enum.reduce_while(1..10, current, fn _, candidate ->
            simulated = Combat.step(candidate.resolution.duel, %{auto: true})

            if simulated.battle.finished,
              do: {:halt, candidate},
              else: {:cont, TeamTraining.battle_action(scope, candidate, %{auto: true})}
          end)

        resolved = Combat.step(before_death.resolution.duel, %{auto: true})
        assert resolved.battle.finished
        resources = Combat.result(resolved).results[boss.id]
        :rand.seed(resolved.rng)
        expected = if Enum.random(1..100) <= 90, do: id, else: boss.id
        expected_rng = :rand.export_seed()

        next = TeamTraining.battle_action(scope, before_death, %{auto: true})
        duel = next.resolution.duel
        assert duel.battle.initiator_id == expected
        assert duel.rng == expected_rng
        turn = Combat.next_turn(duel)
        assert turn.attacker.hero_id == expected
        roshan = Enum.find([turn.attacker, turn.defender], &(&1.hero_id == boss.id))
        assert roshan.current_hp == resources.hp
        assert roshan.current_mp == resources.energy
        next
      end)
    end
  end

  test "saved Roshan retries regain the missing ultimate without resetting health or energy", %{run: run} do
    ready = %{run | turns_left: 0, league_tier: 5, goal: 6}
    boss = TeamTraining.boss_preview(ready)
    skills = Enum.reject(boss.hero.skills, & &1.ultimate)
    saved = %{boss | hp: 999, energy: 17, hero: %{boss.hero | skills: skills}}
    retry = %{ready | boss: saved, boss_attempts: 1}
    preview = TeamTraining.boss_preview(retry)
    assert preview.hp == 999
    assert preview.energy == 17
    assert Enum.count(preview.hero.skills, &(&1.code == "boss_ult")) == 1

    pending = TeamTraining.league(retry) |> TeamTraining.active_encounter()
    assert hd(pending.dire).hp == 999
    assert Enum.count(pending.duel.battle.defender.skills, &(&1.code == "boss_ult")) == 1
  end

  defp grant(run, id, gold, xp) do
    update_in(run.heroes[id], &Loadouts.grant_farm(%{&1 | auto_buy: false}, gold, xp, run.catalog))
  end

  @tag :persisted
  test "saved target lists survive refreshes and stale tabs cannot start a second battle", %{
    scope: scope,
    record: record
  } do
    {:ok, record} = TeamRuns.update(scope, record, &easy_target/1)
    before = TeamRuns.state(record)
    {:ok, selected} = TeamRuns.update(scope, record, &TeamTraining.select(&1, 2))
    assert TeamRuns.state(selected).targets == before.targets
    assert {:error, :stale} = TeamRuns.update(scope, record, &TeamTraining.battle(&1, hd(before.targets[1]).id))
    {:ok, record} = TeamRuns.update(scope, selected, &TeamTraining.select(&1, 1))
    {:ok, pending} = TeamRuns.update(scope, record, &TeamTraining.battle(&1, hd(before.targets[1]).id))
    restored = TeamRuns.state(TeamRuns.get!(scope, pending.id))
    assert restored.phase == :engagement
    assert length(TeamRuns.encounters(scope, pending.id)) == 1
    {:ok, completed} = TeamRuns.update(scope, pending, &finish_team(&1, scope))
    assert TeamRuns.state(completed).phase == :playing
    assert length(TeamRuns.encounters(scope, completed.id)) == 1
    {other, _} = team_account()
    assert_raise Ecto.NoResultsError, fn -> TeamRuns.get!(other, completed.id) end

    assert_raise Ecto.NoResultsError, fn ->
      TeamRuns.encounter!(other, completed.id, hd(TeamRuns.encounters(scope, completed.id)).id)
    end
  end
end
