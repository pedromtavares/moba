defmodule MobaWeb.V2.DuelChallengeLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "challenges appear across preview pages and declining updates both players", %{conn: conn} do
    hero = create_base_hero()
    other = create_base_hero()
    {:ok, sender_page, _} = live(init_test_session(conn, player_id: hero.player_id), "/base")
    {:ok, receiver_page, _} = live(init_test_session(conn, player_id: other.player_id), "/hero/#{other.id}")
    sender = find_live_child(sender_page, "duel-challenges")
    receiver = find_live_child(receiver_page, "duel-challenges")

    Game.duel_challenge(hero.player, other.player)
    assert has_element?(sender, "#duel-challenge-overlay[data-state=pending] #duel-challenge-close")
    assert has_element?(receiver, "#duel-challenge-overlay [role=dialog][aria-modal=true]")
    assert has_element?(receiver, "#duel-challenge-accept")
    assert has_element?(receiver, "#duel-challenge-decline")
    refute has_element?(sender, "#duel-challenge-accept")

    receiver |> element("#duel-challenge-decline") |> render_click()
    refute has_element?(receiver, "#duel-challenge-overlay")
    assert has_element?(sender, "#duel-challenge-overlay[data-state=declined]")
    assert Game.get_player!(hero.player_id).last_challenge_at == nil
    assert Game.list_duels(hero.player) == []

    sender |> element("#duel-challenge-close") |> render_click()
    refute has_element?(sender, "#duel-challenge-overlay")
  end

  test "accept creates a duel and both players stay in the preview routes", %{conn: conn} do
    hero = create_base_hero()
    other = create_base_hero()
    {:ok, sender_page, _} = live(init_test_session(conn, player_id: hero.player_id), "/base")
    {:ok, receiver_page, _} = live(init_test_session(conn, player_id: other.player_id), "/base")
    receiver = find_live_child(receiver_page, "duel-challenges")
    Game.duel_challenge(hero.player, other.player)
    assert has_element?(receiver, "#duel-challenge-accept")

    receiver |> element("#duel-challenge-accept") |> render_click()
    [duel] = Game.list_duels(hero.player)
    assert duel.player_id == hero.player_id
    assert duel.opponent_player_id == other.player_id
    assert_redirect(sender_page, "/arena/#{duel.id}")
    assert_redirect(receiver_page, "/arena/#{duel.id}")
  end

  test "expired challenges cannot be accepted and stale ticks are ignored" do
    token = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        challenge: %{outgoing: false, token: token, expires_at: DateTime.add(DateTime.utc_now(), -1)},
        state: "pending",
        seconds: 1
      }
    }

    {:noreply, expired} = MobaWeb.V2.DuelChallengeLive.handle_info({:challenge_tick, token}, socket)
    assert expired.assigns.state == "expired"
    assert expired.assigns.seconds == 0
    assert {:noreply, ^expired} = MobaWeb.V2.DuelChallengeLive.handle_event("accept", %{}, expired)
    assert {:noreply, ^expired} = MobaWeb.V2.DuelChallengeLive.handle_info({:challenge_tick, make_ref()}, expired)

    {:noreply, rejected_late_accept} = MobaWeb.V2.DuelChallengeLive.handle_event("accept", %{}, socket)
    assert rejected_late_accept.assigns.state == "expired"
  end

  test "canonical pages mount the challenge overlay", %{conn: conn} do
    hero = create_base_hero()
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/base")
    assert has_element?(view, "#duel-challenges")
  end
end
