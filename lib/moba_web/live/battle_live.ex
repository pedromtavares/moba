defmodule MobaWeb.BattleLive do
  use MobaWeb, :live_view

  alias MobaWeb.{BattleView, TutorialComponent}

  def mount(_, session, socket) do
    with socket = socket_init(session["player_id"], socket) do
      {:ok, socket}
    end
  end

  def handle_params(params, _uri, socket) do
    with socket = battle_assigns(params, socket) do
      if connected?(socket), do: MobaWeb.subscribe("battle-#{params["id"]}")

      {:noreply, socket}
    end
  end

  def handle_event(
        "next-turn",
        %{"skill_id" => skill_id, "item_id" => item_id, "hero_id" => hero_id},
        %{assigns: %{battle: %{id: battle_id}}} = socket
      ) do
    with battle = Engine.get_battle!(battle_id),
         skill = skill_id != "" && Game.get_skill!(skill_id),
         item = item_id != "" && Game.get_item!(item_id),
         last_turn = Engine.last_turn(battle),
         valid_attacker? = is_nil(last_turn) || last_turn.defender.hero_id == String.to_integer(hero_id) do
      if valid_attacker? do
        %{assigns: %{battle: battle}} = socket = next_turn(socket, battle, %{skill: skill, item: item}, last_turn)

        {:noreply,
         socket
         |> check_tutorial(battle)
         |> assign(snapshot: battle.attacker_snapshot)}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("check-timer", _, %{assigns: %{battle: %{id: id}}} = socket) do
    with battle = Engine.get_battle!(id),
         last_turn = Engine.last_turn(battle),
         timer = turn_timer(last_turn, battle) do
      if timer < 0 do
        {:noreply, next_turn(socket, battle, %{auto: true}, last_turn)}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("next-battle", %{"id" => id}, %{assigns: %{battle: battle}} = socket) do
    latest = Engine.latest_battle(battle.attacker.id)

    if latest.type == "league" && latest.id != String.to_integer(id) do
      {:noreply, socket |> push_patch(to: Routes.live_path(socket, MobaWeb.BattleLive, latest.id))}
    else
      {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.TrainingLive))}
    end
  end

  def handle_info({:turn, %{battle_id: battle_id, turn_number: turn_number}}, socket) do
    with battle = Engine.get_battle!(battle_id),
         turn = Engine.build_turn(battle) do
      {:noreply, turn_assigns(socket, battle, turn, turn_number)}
    end
  end

  def render(assigns) do
    BattleView.render("show.html", assigns)
  end

  defp battle_assigns(params, socket) do
    with battle = Engine.get_battle!(params["id"]),
         last_turn = Engine.last_turn(battle),
         turn = Engine.build_turn(battle) do
      assign(socket,
        action_turn_number: nil,
        battle: battle,
        debug: Map.get(params, "debug"),
        hide_sidebar: !battle.finished,
        last_turn: last_turn,
        skill: BattleView.preselected_skill(turn.attacker, turn),
        snapshot: battle.attacker_snapshot,
        turn: turn,
        turn_timer: turn_timer(last_turn, battle)
      )
    end
  end

  defp check_tutorial(socket, %{attacker_snapshot: %{league_step: 0}, type: "league"} = battle) do
    if battle.winner_id == battle.attacker_id do
      TutorialComponent.next_step(socket, 11)
    else
      socket
    end
  end

  defp check_tutorial(socket, _), do: socket

  defp next_turn(socket, battle, battle_opts, last_turn) do
    with battle = Engine.continue_battle!(battle, battle_opts),
         next_turn = Engine.build_turn(battle),
         turn_number = (last_turn && last_turn.number + 1) || 1 do
      MobaWeb.broadcast("battle-#{battle.id}", :turn, %{battle_id: battle.id, turn_number: turn_number})
      turn_assigns(socket, battle, next_turn, turn_number)
    end
  end

  defp socket_init(player_id, socket) do
    %{assigns: %{current_player: current_player}} =
      socket = assign_new(socket, :current_player, fn -> player_id && Game.get_player!(player_id) end)

    assign(socket, tutorial_step: current_player && current_player.tutorial_step)
  end

  defp turn_assigns(socket, battle, turn, turn_number) do
    with last_turn = Engine.last_turn(battle) do
      assign(socket,
        action_turn_number: turn_number,
        battle: battle,
        last_turn: last_turn,
        skill: BattleView.preselected_skill(turn.attacker, turn),
        turn: turn,
        turn_timer: turn_timer(last_turn, battle)
      )
    end
  end

  defp turn_timer(last_turn, battle) do
    turn_time = (last_turn && last_turn.inserted_at) || battle.inserted_at
    target = Timex.shift(turn_time, seconds: Moba.turn_timer_in_seconds())
    Timex.diff(target, Timex.now(), :seconds)
  end
end
