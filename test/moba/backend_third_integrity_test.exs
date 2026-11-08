defmodule Moba.BackendThirdIntegrityTest do
  use MobaWeb.ConnCase
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias Moba.Repo

  test "stale purchases spend current gold and preserve a consistent inventory" do
    a = alternate_item()
    b = Game.get_item_by_code!("satanic")
    gold = max(Game.item_price(a), Game.item_price(b))
    hero = create_base_hero(%{gold: gold})
    Game.buy_item!(hero, a)
    Game.buy_item!(hero, b)
    stored = Game.get_hero!(hero.id)
    assert Enum.map(stored.items, & &1.code) == [a.code]
    assert stored.gold == gold - Game.item_price(a)
    assert Map.take(stored, Map.keys(Game.item_attributes(stored.items))) == Game.item_attributes(stored.items)
  end

  test "a stale sale cannot sell an item twice or erase a later purchase" do
    hero = create_base_hero(%{gold: 100_000}) |> Game.buy_item!(alternate_item())
    first = Game.sell_item!(hero, alternate_item())
    Game.buy_item!(first, base_item())
    result = Game.sell_item!(hero, alternate_item())
    assert Enum.map(result.items, & &1.code) == [base_item().code]
    assert result.gold == first.gold - Game.item_price(base_item())
  end

  test "stale transmutation cannot consume ingredients already sold" do
    ingredients = base_normal_items()
    hero = create_base_hero(%{gold: 100_000}) |> Game.update_hero!(%{}, ingredients)
    Game.sell_item!(hero, hd(ingredients))
    result = Game.transmute_item!(hero, ingredients, base_rare_item())
    refute Enum.any?(result.items, &(&1.id == base_rare_item().id))
    refute Enum.any?(result.items, &(&1.id == hd(ingredients).id))
  end

  test "two stale skill upgrades cannot spend one point twice" do
    hero = create_base_hero(%{level: 20, skill_levels_available: 1})
    [a, b | _] = Enum.reject(hero.skills, & &1.ultimate)
    Game.level_up_skill!(hero, a.code)
    Game.level_up_skill!(hero, b.code)
    stored = Game.get_hero!(hero.id)
    assert Enum.find(stored.skills, &(&1.code == a.code)).level == 2
    assert Enum.find(stored.skills, &(&1.code == b.code)).level == 1
    assert stored.skill_levels_available == 0
  end

  test "replaying stale quest progression pays the prize once and retains newer codes" do
    player = create_player!(%{pve_progression: %{season_codes: ["another_avatar"]}})
    hero = create_base_hero(%{league_tier: Moba.platinum_league_tier()}, player)
    before = Accounts.get_user!(player.user_id).shard_count
    Game.Quests.track_pve_progression!(hero)
    Game.Quests.track_pve_progression!(hero)
    assert Accounts.get_user!(player.user_id).shard_count == before + 200
    assert Game.get_player!(player.id).pve_tier == 1

    assert Enum.sort(Game.get_player!(player.id).pve_progression.season_codes) ==
             Enum.sort(["another_avatar", hero.avatar.code])
  end

  test "unfinished combat and archived heroes cannot start farming" do
    hero = create_base_hero(%{pve_tier: 2, total_hp: 100_000, pve_current_turns: 10})
    target = Game.list_targets(hero) |> hd() |> then(&Game.get_target!(&1.id))
    battle = Game.start_pve_battle!(target)
    refute battle.finished
    assert Game.start_farming!(hero, "mining", 2).pve_state == "alive"
    assert Engine.pending_battle(hero.id).id == battle.id

    archived = create_base_hero(%{archived_at: DateTime.utc_now()})
    assert Game.start_farming!(archived, "meditating", 1).pve_state == "alive"
  end

  test "unrelated task failures leave completed match results intact", %{conn: conn} do
    player = create_player!(%{total_matches: 1})
    opponent = create_player!(%{total_matches: 1})
    match = Game.manual_matchmaking!(player)
    match = Game.Matches.update!(match, %{phase: "scored", winner_id: opponent.id})
    viewer = create_player!()
    {:ok, view, _} = conn |> log_in_player(player_id: viewer.id) |> live("/matches/#{match.id}")
    send(view.pid, {:DOWN, make_ref(), :process, self(), :task_failed})
    render(view)
    stored = Game.get_match!(match.id)
    assert stored.phase == "scored"
    assert stored.winner_id == opponent.id
  end

  test "a known match worker failure reloads the committed result without deleting battles" do
    player = create_player!(%{total_matches: 1})
    create_player!(%{total_matches: 1})
    match = Game.manual_matchmaking!(player)
    ref = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_player: player,
        match: match,
        match_task_ref: ref,
        preview: true,
        starting: true
      }
    }

    {:noreply, result} = MobaWeb.V2.MatchLive.handle_info({:DOWN, ref, :process, self(), :failed}, socket)
    refute result.assigns.starting
    refute result.assigns.match_task_ref
    assert result.assigns.flash["error"] =~ "try again"
    assert Game.get_match!(match.id).player_picks == match.player_picks
  end

  test "rating changes and head-to-head wins accumulate from fresh player state" do
    player = create_player!(%{pvp_points: 100})
    opponent = create_player!()
    Game.Players.duel_update!(player, %{rating_change: 10, loser_id: opponent.id})
    Game.Players.duel_update!(player, %{rating_change: 20, loser_id: opponent.id})
    stored = Game.get_player!(player.id)
    assert stored.pvp_points == 130
    assert stored.duel_score[to_string(opponent.id)] == 2
    Game.Players.duel_update!(player, %{rating_change: -200})
    assert Game.get_player!(player.id).pvp_points == 0
  end

  test "separate scored matches retain both results and cannot be scored twice" do
    player = create_player!(%{pvp_points: 100})
    opponent = create_player!(%{pvp_points: 100})

    attrs = %{
      player_id: player.id,
      opponent_id: opponent.id,
      player_picks: [],
      opponent_picks: [],
      generated_picks: [],
      type: "manual",
      winner_id: player.id
    }

    one = Game.Matches.create!(attrs)
    two = Game.Matches.create!(attrs)
    first = Game.continue_match!(one)
    second = Game.continue_match!(two)
    Game.continue_match!(one)
    stored = Game.get_player!(player.id)
    assert stored.total_matches == 2
    assert stored.daily_wins == 2
    assert stored.pvp_points == 100 + first.rewards.attacker_pvp_points + second.rewards.attacker_pvp_points
  end

  test "chat accepts three messages across rooms then requires five quiet seconds" do
    user = create_user()

    for channel <- ["community", "duel-1", "duel-2"] do
      assert {:ok, _} = Accounts.create_message(%{user_id: user.id, body: "hello", channel: channel, topic: "general"})
    end

    assert {:error, :rate_limited} = Accounts.create_message(%{user_id: user.id, body: "fourth", channel: "community"})
    assert {:error, :rate_limited} = Accounts.create_message(%{"user_id" => user.id, "body" => "another tab"})
    assert Repo.aggregate(from(m in Accounts.Schema.Message, where: m.user_id == ^user.id), :count) == 3
    other = create_user()

    assert {:ok, _} =
             Accounts.create_message(%{
               user_id: other.id,
               body: "another player",
               channel: "community",
               topic: "general"
             })

    Repo.update!(Ecto.Changeset.change(user, chat_last_message_at: DateTime.add(DateTime.utc_now(), -5)))

    assert {:ok, _} =
             Accounts.create_message(%{user_id: user.id, body: "after cooldown", channel: "community", topic: "general"})

    assert Accounts.get_user!(user.id).chat_burst_count == 1
  end

  test "removed community chat cannot receive messages through a LiveView event", %{conn: conn} do
    player = create_player!()
    {:ok, view, _} = conn |> log_in_player(player_id: player.id) |> live("/community")

    render_submit(view, "create-message", %{"message" => %{"body" => "Forged message"}})
    refute has_element?(view, "#community-message-form")
    assert Repo.aggregate(from(m in Accounts.Schema.Message, where: m.user_id == ^player.user_id), :count) == 0
  end

  test "current rankings exclude past-season players and preserve their stored ranks" do
    old = Repo.insert!(%Game.Schema.Season{active: false})
    player = create_player!(%{pvp_points: 999_999, ranking: 1, season_ranking: 1, total_matches: 1})
    Repo.update!(Ecto.Changeset.change(player, season_id: old.id))
    current = create_player!(%{pvp_points: 100, ranking: 2, season_ranking: 2, total_matches: 1})

    for ranking <- [Game.season_points_ranking(1000), Game.daily_ranking(1000), Game.season_ranking(1000)] do
      refute Enum.any?(ranking, &(&1.id == player.id))
      assert Enum.any?(ranking, &(&1.id == current.id))
    end

    Game.update_season_ranking!()
    Game.update_daily_ranking!()
    assert Game.get_player!(player.id).season_ranking == 1
    assert Game.get_player!(player.id).ranking == 1
  end

  test "cached leaderboards from a prior season are refreshed" do
    old = Repo.insert!(%Game.Schema.Season{active: false})
    former = create_player!(%{ranking: 1, season_ranking: 1})
    former = Repo.update!(Ecto.Changeset.change(former, season_id: old.id))
    player = create_player!(%{ranking: 1, season_ranking: 1})
    Cachex.put(:game_cache, "daily_ranking", [former])
    Cachex.put(:game_cache, "season_ranking", [former])

    on_exit(fn ->
      Cachex.del(:game_cache, "daily_ranking")
      Cachex.del(:game_cache, "season_ranking")
    end)

    for ranking <- [Moba.daily_ranking(), Moba.season_ranking()] do
      assert Enum.any?(ranking, &(&1.id == player.id))
      refute Enum.any?(ranking, &(&1.id == former.id))
    end
  end

  test "cleanup archives an abandoned hero when the current pointer is nil" do
    player = create_player!()
    hero = create_base_hero(%{}, player)
    Game.update_player!(Game.get_player!(player.id), %{current_pve_hero_id: nil})
    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-8 * 86400) |> NaiveDateTime.truncate(:second)
    Repo.update_all(from(h in Game.Schema.Hero, where: h.id == ^hero.id), set: [inserted_at: old, updated_at: old])
    Moba.Cleaner.cleanup_old_records()
    assert Game.get_hero!(hero.id).archived_at
    recent = create_base_hero(%{}, Game.get_player!(player.id))
    Game.update_player!(Game.get_player!(player.id), %{current_pve_hero_id: nil})
    Moba.Cleaner.cleanup_old_records()
    refute Game.get_hero!(recent.id).archived_at
  end
end
