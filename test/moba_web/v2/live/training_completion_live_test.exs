defmodule MobaWeb.V2.TrainingCompletionLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "rank-up celebrates the earned rank and shows its rewards, not the next rank", %{conn: conn} do
    hero = completed_hero(Moba.platinum_league_tier())
    player = rank_up(hero)
    conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#training-completion[data-outcome='rank-up']")
    assert has_element?(view, "#training-completion-title", "Novice")
    assert has_element?(view, "#completion-shards", "+200")
    assert has_element?(view, "#completion-continue[href='/base']")
    assert has_element?(view, "#completion-view-rewards[data-target='#pve-tier-rewards']")
    assert has_element?(view, "#pve-tier-rewards[data-tier='1'][data-earned='true']")
    assert has_element?(view, "#pve-tier-rewards-label", "Novice")
    assert has_element?(view, "#progression-shards[href='/tavern']", "+200")
    assert has_element?(view, "#progression-bonus", Game.get_quest(1).training_bonus)
    assert has_element?(view, "#progression-close[data-dismiss='modal']")
    assert has_element?(view, "#progression-dismiss[data-dismiss='modal']")
  end

  test "qualified training returns to base without claiming a rank reward", %{conn: conn} do
    hero = completed_hero(Moba.platinum_league_tier())
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#training-completion[data-outcome='qualified']")
    assert has_element?(view, "#completion-continue[href='/base']")
    refute has_element?(view, "#completion-shards")
    refute has_element?(view, "#completion-view-rewards")
  end

  test "lower league completion offers another training run", %{conn: conn} do
    hero = completed_hero(1)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#training-completion[data-outcome='retry']")
    assert has_element?(view, "#completion-continue[href='/invoke']")
    refute has_element?(view, "#completion-shards")
  end

  test "guest rank-up continues to the arena", %{conn: conn} do
    guest = Game.create_player!(%{user_id: nil, tutorial_step: 19})
    hero = completed_hero(Moba.platinum_league_tier(), guest)
    player = rank_up(hero)
    conn = init_test_session(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#completion-continue[href='/arena']")
  end

  test "an active hero does not show a completion screen", %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    refute has_element?(view, "#training-completion")
  end

  test "final rank completion shows Invoker rewards without advancing past the last rank", %{conn: conn} do
    hero = completed_hero(Moba.max_league_tier())
    player = rank_up(hero, 7)
    conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#training-completion-title", "Invoker")
    assert has_element?(view, "#pve-tier-rewards[data-tier='7'][data-earned='true']")
    assert has_element?(view, "#progression-shards", "+5000")
    refute has_element?(view, "#progression-bonus")
  end

  test "base previews the next rank and omits absent bonuses", %{conn: conn} do
    hero = create_base_hero()
    player = Game.update_player!(hero.player, %{pve_tier: 1})
    conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)
    {:ok, view, _} = live(conn, "/base")

    assert has_element?(view, "#pve-tier-rewards[data-tier='2'][data-earned='false']")
    assert has_element?(view, "#pve-tier-rewards-label", "Adept")
    assert has_element?(view, "#progression-shards", "+300")
    assert has_element?(view, "#progression-difficulty", Game.get_quest(2).difficulty)
    refute has_element?(view, "#progression-bonus")
  end

  defp completed_hero(tier, player \\ create_player!()) do
    create_base_hero(
      %{league_tier: tier, finished_at: DateTime.utc_now() |> DateTime.truncate(:second)},
      player
    )
  end

  defp rank_up(hero, tier \\ 1) do
    Game.update_player!(Game.get_player!(hero.player_id), %{
      pve_tier: tier,
      pve_progression: %{history: %{to_string(tier) => Timex.format!(hero.finished_at, "{ISO:Extended:Z}")}}
    })
  end
end
