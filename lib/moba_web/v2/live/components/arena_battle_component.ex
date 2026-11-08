defmodule MobaWeb.V2.ArenaBattleComponent do
  @moduledoc "Manual Arena combat using the shared cinematic battlefield and training controls."
  use MobaWeb, :v2_live_component
  import MobaWeb.CoreComponents, only: [icon: 1]
  alias Moba.Game.Arena
  alias MobaWeb.V2.BattleLive
  alias MobaWeb.V2.Components.CombatScene
  embed_templates "arena_battle_component/*"

  def mount(socket), do: {:ok, assign(socket, auto_mode: :none, mode_token: 0, show_combat_log: false)}

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> load()}
  end

  def handle_event("toggle-combat-log", _, socket),
    do: {:noreply, assign(socket, show_combat_log: !socket.assigns.show_combat_log)}

  def handle_event(event, params, socket) do
    scope = MobaWeb.V2.Hooks.TeamAccess.authorize(socket.assigns.access_session)

    if scope && scope.user && scope.user.id == socket.assigns.match.player.user_id do
      action(event, params, assign(socket, current_scope: scope))
    else
      {:noreply, socket}
    end
  end

  defp action("pause", _, socket),
    do: {:noreply, socket |> assign(auto_mode: :none, mode_token: socket.assigns.mode_token + 1) |> load()}

  defp action(event, _, %{assigns: %{active: true}} = socket) when event in ["auto-battle", "auto-match"] do
    {:noreply,
     socket
     |> assign(
       auto_mode: if(event == "auto-match", do: :match, else: :battle),
       mode_token: socket.assigns.mode_token + 1
     )
     |> load()}
  end

  defp action("next-turn", params, %{assigns: %{can_act: true}} = socket) do
    if params["hero_id"] == to_string(socket.assigns.control_hero.id) do
      {:noreply, mutate(socket, %{skill_id: params["skill_id"], item_id: params["item_id"]})}
    else
      {:noreply, load(socket)}
    end
  end

  defp action("next-battle", _, socket), do: {:noreply, mutate(socket, :next)}

  defp action("training-playback-ready", %{"frame" => frame}, socket) do
    a = socket.assigns

    cond do
      frame != a.frame ->
        {:noreply, socket}

      a.active && !a.battle.finished && (a.auto_mode != :none || a.turn.attacker.player_id != a.match.player_id) ->
        {:noreply, mutate(socket, %{auto: true})}

      a.active && a.battle.finished && a.auto_mode == :match ->
        {:noreply, mutate(socket, :next)}

      true ->
        {:noreply, socket}
    end
  end

  defp action(_, _, socket), do: {:noreply, socket}

  defp mutate(socket, action) do
    a = socket.assigns
    Arena.play_match(a.current_scope, a.match.id, a.battle.id, length(a.battle.turns), action)

    if action == :next && a.battle_id,
      do: push_patch(socket, to: ~p"/matches/#{a.match.id}/battles"),
      else: load(socket)
  end

  defp load(socket) do
    a = socket.assigns
    match = Game.get_match!(a.match_id)
    battles = Engine.list_match_battles(match.id)
    latest = List.last(battles)
    battle = Enum.find(battles, &(to_string(&1.id) == a.battle_id)) || latest
    battle = Engine.get_battle!(battle.id)
    following = Enum.at(battles, Enum.find_index(battles, &(&1.id == battle.id)) + 1)
    turn = Engine.build_turn(battle)
    player = %{id: match.player_id}
    owner? = a.current_scope.user && match.player.user_id == a.current_scope.user.id
    active = !!owner? && match.interactive && battle.id == latest.id && match.phase == "started"
    mode = if !active || (battle.finished && a.auto_mode == :battle), do: :none, else: a.auto_mode

    control_turn =
      if turn.attacker.player_id == player.id,
        do: turn,
        else: %{turn | attacker: turn.defender, defender: turn.attacker}

    hero = Enum.find([battle.attacker, battle.defender], &(&1.id == control_turn.attacker.hero_id))
    # Controls and tooltips use the same frozen loadout as the engine, even if the collection is edited elsewhere.
    hero = GH.match_hero_loadout(hero, [battle])

    initial = BattleLive.initial_turn(battle, battles) || turn
    frame = "arena-#{battle.id}:#{length(battle.turns)}:#{a.mode_token}"

    enabled =
      active &&
        ((!battle.finished && (mode != :none || turn.attacker.player_id != player.id)) ||
           (battle.finished && mode == :match))

    scene =
      CombatScene.build(battle, initial, turn, player)
      |> Map.merge(%{
        context: "Arena · 3v3",
        turnDeadline: nil,
        fullReplay: true,
        trainingPlayback: %{enabled: enabled, frame: frame}
      })

    can_act = active && !battle.finished && turn.attacker.player_id == player.id && mode == :none
    recorded_battles = battles |> Enum.take_while(&(&1.id <= battle.id)) |> Enum.reverse()

    lineups =
      for {side, picks, name} <- [
            {:player, match.player_picks, username(match.player)},
            {:opponent, match.opponent_picks, username(match.opponent)}
          ] do
        owner = if side == :player, do: match.player_id, else: match.opponent_id

        units =
          for pick <- Enum.reject(picks, &is_nil/1) do
            state =
              Enum.find_value(recorded_battles, fn fight ->
                last = List.last(fight.turns)

                if last,
                  do: Enum.find([last.attacker, last.defender], &(&1.hero_id == pick.id && &1.player_id == owner))
              end)

            %{
              hero: pick,
              hp: if(state, do: max(0, round(state.current_hp)), else: pick.total_hp + pick.item_hp),
              total: if(state, do: state.total_hp, else: pick.total_hp + pick.item_hp),
              fallen: !!state && state.current_hp <= 0
            }
          end

        %{side: side, name: name, units: units}
      end

    assign(socket,
      match: match,
      battles: battles,
      battle: battle,
      following: following,
      match_over: match.phase in ["finished", "scored"] && battle.id == latest.id,
      turn: turn,
      initial_turn: initial,
      combat_scene: scene,
      frame: frame,
      lineups: lineups,
      active: active,
      auto_mode: mode,
      can_act: can_act,
      control_turn: control_turn,
      control_hero: hero,
      hero: hero,
      controls_disabled: !can_act,
      preview: true,
      debug: false,
      manual_view: true,
      action_turn_number: nil,
      action_controls_id: "arena-manual-turn-#{battle.id}-#{turn.number}",
      active_hero_id: if(can_act, do: hero.id),
      current_player: player,
      event_target: a.myself,
      turn_timer: 0,
      skill: Engine.preselected_skill(control_turn),
      last_turn: List.last(battle.turns),
      replay: %{kind: :arena},
      won: match.winner_id == match.player_id
    )
  end

  defp chapter_path(match, battle) do
    ~p"/matches/#{match.id}/battles?#{[battle: battle.id]}"
  end

  def render(assigns), do: encounter(assigns)
end
