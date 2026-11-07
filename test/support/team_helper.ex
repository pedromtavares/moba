defmodule Test.TeamHelper do
  @moduledoc false
  alias Moba.{Accounts, Game, Repo}
  alias Game.{TeamRuns, TeamTraining}
  alias Game.Training.Combat

  def team_account(tier \\ 2) do
    player = Test.GameHelper.create_player!(%{pve_tier: tier}) |> then(&Game.get_player!(&1.id))
    user = player.user |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
    player = Game.get_player!(player.id)
    {%{user: user}, player}
  end

  def team_picks(scope) do
    codes = if scope.user, do: Accounts.unlocked_codes_for(scope.user), else: []
    skills = Game.list_creation_skills(1, codes) |> Enum.take(3) |> Enum.map(&to_string(&1.id))

    Game.list_creation_avatars(codes)
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.map(fn {avatar, i} -> %{"avatar" => to_string(avatar.id), "skills" => skills, "name" => "Hero #{i}"} end)
  end

  def team_run(scope, player) do
    {:ok, record} = TeamRuns.draft(scope, player)

    {:ok, record} = TeamRuns.update(scope, record, &start_team(scope, &1))
    record
  end

  def team_state(scope, player) do
    TeamTraining.draft(scope, player, Game.Training.Loadouts.catalog()) |> then(&start_team(scope, &1))
  end

  defp start_team(%{user: _} = scope, %{phase: :draft} = run) do
    Enum.reduce(team_picks(scope), run, fn pick, current ->
      {:ok, updated} = TeamTraining.add_pick(scope, current, pick)
      updated
    end)
    |> TeamTraining.begin_run()
  end

  def simple_unit(h, hp, atk) do
    hero = %{
      h.hero
      | total_hp: hp,
        atk: atk,
        skills: [],
        skill_order: [],
        items: [],
        item_order: [],
        inventory_order: [],
        item_hp: 0,
        item_mp: 0,
        item_atk: 0,
        item_power: 0,
        item_armor: 0,
        item_speed: 0,
        armor: 0,
        power: 0
    }

    %{h | hero: hero, hp: hp, inventory: [], auto_buy: false}
  end

  def easy_target(run, id \\ 1, index \\ 0) do
    unit = simple_unit(run.heroes[id], 5000, 10_000)
    unit = %{unit | hero: %{unit.hero | speed: 100, item_speed: 0}}
    run = put_in(run.heroes[id], unit)
    target = Enum.at(run.targets[id], index)
    opponent = simple_unit(target.opponent, 20, 1)
    target = %{target | opponent: opponent, defender: opponent.hero}
    run |> put_in([:targets, id], List.replace_at(run.targets[id], index, target)) |> TeamTraining.select(id)
  end

  def finish_team(run, scope) do
    Enum.reduce_while(1..1000, run, fn _, current ->
      if current.phase == :engagement,
        do: {:cont, TeamTraining.battle_action(scope, current, %{auto: true})},
        else: {:halt, current}
    end)
  end

  def simple_league(run) do
    e = TeamTraining.active_encounter(run)

    units =
      Map.new(e.units, fn {id, h} ->
        {id, simple_unit(h, if(id < 1000, do: 5000, else: 100), if(id < 1000, do: 60, else: 1))}
      end)

    r = hd(e.remaining.radiant)
    d = hd(e.remaining.dire)
    duel = Combat.new_duel(units[r], units[d])

    e = %{
      e
      | units: units,
        radiant: Enum.map(e.radiant, &units[&1.id]),
        dire: Enum.map(e.dire, &units[&1.id]),
        duel: duel,
        battles: [duel.battle]
    }

    %{run | encounters: [e], resolution: %{duel: duel}}
  end

  def league_with_casualty(run) do
    run = simple_league(run)
    e = TeamTraining.active_encounter(run)
    units = Map.update!(e.units, 1, &simple_unit(&1, 1, 1))
    duel = Combat.new_duel(units[1], units[hd(e.remaining.dire)])
    e = %{e | units: units, radiant: Enum.map(e.radiant, &units[&1.id]), duel: duel, battles: [duel.battle]}
    %{run | encounters: [e], resolution: %{duel: duel}}
  end
end
