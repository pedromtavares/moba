defmodule MobaWeb.BattleLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.{BattleView, Tutorial}

  def mount(_, session, socket) do
    %{assigns: %{current_user: current_user}} =
      socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    socket = assign_new(socket, :current_hero, fn -> current_user && Game.current_pve_hero(current_user) end)

    {:ok,
     assign(socket,
       hero: nil,
       skill: nil,
       item: nil,
       turn: nil,
       last_turn: nil,
       action_turn_number: nil,
       show_shop: false,
       tutorial_step: current_user && current_user.tutorial_step
     )}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    battle = Engine.get_battle!(id)
    turn = Engine.next_battle_turn(battle)
    last_turn = Engine.last_turn(battle)

    if connected?(socket) && battle.type == "duel" do
      MobaWeb.subscribe("battle-#{battle.id}")
    end

    {:noreply,
     assign(socket,
       battle: battle,
       debug: Map.get(params, "debug"),
       hero: battle.attacker_snapshot,
       turn: turn,
       hide_sidebar: !battle.finished,
       last_turn: last_turn,
       skill: BattleView.preselected_skill(turn.attacker, turn),
       turn_timer: turn_timer(last_turn, battle)
     )}
  end

  def handle_event("next-turn", %{"skill_id" => skill_id, "item_id" => item_id, "hero_id" => hero_id}, %{assigns: %{battle: %{id: battle_id}}} = socket) do
    battle = Engine.get_battle!(battle_id)
    skill = skill_id != "" && Game.get_skill!(skill_id)
    item = item_id != "" && Game.get_item!(item_id)
    current_turn = Engine.last_turn(battle)
    if is_nil(current_turn) || current_turn.defender.hero_id == String.to_integer(hero_id) do
      battle = Engine.continue_battle!(battle, %{skill: skill, item: item})
      next_turn = Engine.next_battle_turn(battle)
      turn_number = (current_turn && current_turn.number + 1) || 1

      MobaWeb.broadcast("battle-#{battle.id}", "turn", %{battle_id: battle.id, turn_number: turn_number})

      {:noreply,
       socket
       |> check_tutorial(battle)
       |> turn_assigns(battle, next_turn, turn_number)
       |> assign(hero: battle.attacker_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("check-timer", _, %{assigns: %{battle: %{id: id}}} = socket) do
    battle = Engine.get_battle!(id)
    last_turn = Engine.last_turn(battle)
    timer = turn_timer(last_turn, battle)

    if timer < 0 do
      battle = Engine.continue_battle!(battle, %{auto: true})
      next_turn = Engine.next_battle_turn(battle)
      turn_number = (last_turn && last_turn.number + 1) || 1
      MobaWeb.broadcast("battle-#{battle.id}", "turn", %{battle_id: battle.id, turn_number: turn_number})

      {:noreply, turn_assigns(socket, battle, next_turn, turn_number)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("next-battle", %{"id" => id}, socket) do
    battle =
      socket.assigns.battle.attacker.id
      |> Engine.latest_battle()

    if battle.id != String.to_integer(id) && battle.type == "league" do
      {:noreply, socket |> push_patch(to: Routes.live_path(socket, MobaWeb.BattleLiveView, battle.id))}
    else
      {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.TrainingLiveView))}
    end
  end

  def handle_info({"turn", %{battle_id: battle_id, turn_number: turn_number}}, socket) do
    battle = Engine.get_battle!(battle_id)
    turn = Engine.next_battle_turn(battle)

    {:noreply, turn_assigns(socket, battle, turn, turn_number)}
  end

  def render(assigns) do
    BattleView.render("show.html", assigns)
  end

  defp check_tutorial(socket, battle) do
    snapshot = battle.attacker_snapshot

    if battle.type == "league" && snapshot.league_step == 0 && battle.winner &&
         battle.winner.id == battle.attacker.id do
      Tutorial.next_step(socket, 11)
    else
      socket
    end
  end

  defp turn_assigns(socket, battle, turn, turn_number) do
    last_turn = Engine.last_turn(battle)

    assign(socket,
      battle: battle,
      action_turn_number: turn_number,
      last_turn: last_turn,
      turn: turn,
      skill: BattleView.preselected_skill(turn.attacker, turn),
      item: nil,
      turn_timer: turn_timer(last_turn, battle)
    )
  end

  defp turn_timer(last_turn, battle) do
    turn_time = (last_turn && last_turn.inserted_at) || battle.inserted_at
    target = Timex.shift(turn_time, seconds: Moba.turn_timer_in_seconds())
    Timex.diff(target, Timex.now(), :seconds)
  end
end
