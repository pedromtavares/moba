defmodule Moba.Game.ArenaInteractiveTest do
  use Moba.DataCase
  import Test.GameHelper
  alias Moba.{Game, Engine}
  alias Moba.Game.{Arena, Matches}

  setup do
    player = create_player!(%{pve_tier: 1})
    opponent = create_player!(%{pve_tier: 1})
    avatar = strong_avatar()
    weak = weak_avatar()
    picks = for n <- 1..3, do: Game.create_hero!(%{name: "Hero #{n}", finished_at: Timex.now(), league_tier: 6, pve_tier: 1}, player, avatar, base_skills())
    enemies = for n <- 1..3, do: Game.create_hero!(%{name: "Enemy #{n}"}, opponent, weak, base_skills())
    match = Matches.create!(%{player_id: player.id, opponent_id: opponent.id, player_picks: [], opponent_picks: Enum.map(enemies, & &1.id), generated_picks: [], type: "manual"})
    player = Game.get_player!(player.id)
    %{player: player, scope: %{user: player.user}, opponent: opponent, match: match, picks: picks}
  end

  test "manual start saves a single unplayed battle and does not score the match", a do
    assert {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    assert match.interactive
    assert match.phase == "started"
    assert [battle] = Engine.list_match_battles(match.id)
    refute battle.finished
    assert battle.turns == []
    assert Game.get_player!(a.player.id).daily_matches == a.player.daily_matches
  end

  test "turns are stale-safe, survivor resources survive reload, and scoring occurs once at the end", a do
    {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    battle = Engine.latest_match_battle(match.id)
    {:ok, _} = Arena.play_match(a.scope, match.id, battle.id, 0, %{skill_id: "", item_id: ""})
    first = Engine.get_battle!(battle.id)
    assert first.finished
    assert Matches.get_match!(match.id).phase == "started"
    assert Game.get_player!(a.player.id).daily_matches == a.player.daily_matches
    Arena.play_match(a.scope, match.id, battle.id, 0, %{auto: true})
    assert length(Engine.get_battle!(battle.id).turns) == 1
    {:ok, _} = Arena.play_match(a.scope, match.id, battle.id, 1, :next)
    next = Engine.latest_match_battle(match.id)
    assert next.id != battle.id
    expected = List.last(first.turns).attacker
    assert next.attacker_initial_hp == round(expected.current_hp + expected.total_hp * 0.2)
    reloaded = Engine.get_battle!(next.id)
    turn = Engine.build_turn(reloaded)
    carried = Enum.find([turn.attacker, turn.defender], &(&1.hero_id == first.winner_id))
    assert carried.current_hp == next.attacker_initial_hp
    complete(a.scope, match.id)
    final = Matches.get_match!(match.id)
    assert final.phase == "scored"
    assert final.winner_id == a.player.id
    assert Game.get_player!(a.player.id).daily_matches == a.player.daily_matches + 1
    last = Engine.latest_match_battle(match.id)
    Arena.play_match(a.scope, match.id, last.id, length(last.turns), :next)
    assert Game.get_player!(a.player.id).daily_matches == a.player.daily_matches + 1
    assert length(Engine.list_match_battles(match.id)) == 3
  end

  test "another account and guests cannot drive an Arena match", a do
    {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    battle = Engine.latest_match_battle(match.id)
    other = Game.get_player!(a.opponent.id)
    assert {:error, :unauthorized} = Arena.play_match(%{user: other.user}, match.id, battle.id, 0, %{auto: true})
    assert {:error, :unauthorized} = Arena.play_match(%{user: nil}, match.id, battle.id, 0, %{auto: true})
    assert Engine.get_battle!(battle.id).turns == []
  end

  defp complete(scope, id, budget \\ 30)
  defp complete(_, _, 0), do: flunk("Arena did not complete within its turn budget")
  defp complete(scope, id, budget) do
    match = Matches.get_match!(id)
    unless match.phase == "scored" do
      battle = Engine.latest_match_battle(id)
      Arena.play_match(scope, id, battle.id, length(battle.turns), if(battle.finished, do: :next, else: %{auto: true}))
      complete(scope, id, budget - 1)
    end
  end
end
