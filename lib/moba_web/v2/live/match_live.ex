defmodule MobaWeb.V2.MatchLive do
  use MobaWeb, :v2_live_view
  on_mount MobaWeb.V2.Hooks.TeamAccess

  import MobaWeb.CoreComponents, only: [icon: 1]

  embed_templates "match_live/*"

  @tick_timeout 500
  @max_tick 15

  def mount(%{"id" => match_id} = params, session, socket) do
    socket = assign(socket, training_record: nil, access_session: session)
    match = Game.get_match!(match_id)

    if match.training_team_id do
      data = Game.TrainingEncounters.for_match!(socket.assigns.current_scope, match.id)
      {:ok, assign(socket, training_record: data.record, training_battle_index: nil)}
    else
      mount_pvp(params, session, socket)
    end
  end

  defp mount_pvp(%{"id" => match_id}, _session, socket) do
    case socket_init(match_id, @max_tick, socket) do
      %{assigns: %{match: %{interactive: true, phase: "scored"}, battles: []}} = socket ->
        {:ok, socket |> put_flash(:info, "This match replay has expired.") |> push_navigate(to: ~p"/arena")}

      socket ->
        {:ok, subscribe_to_match(socket)}
    end
  end

  defp subscribe_to_match(socket) do
    socket =
      attach_hook(socket, :authorize_match_changes, :handle_event, fn event, _, socket ->
        if event in ~w(repeat pick-hero unpick-hero pick-team clear-lineup move-up move-down reorder-lineup start) do
          match = Game.get_match!(socket.assigns.match.id)

          if match.player_id == socket.assigns.current_player.id && is_nil(match.phase) && is_nil(match.winner_id),
            do: {:cont, assign(socket, match: match)},
            else: {:halt, socket}
        else
          {:cont, socket}
        end
      end)

    if connected?(socket) do
      MobaWeb.subscribe(socket.assigns.channel)
    end

    socket
  end

  def handle_event(_, _, %{assigns: %{training_record: record}} = socket) when not is_nil(record),
    do: {:noreply, socket}

  def handle_event("hero-tab", %{"type" => tab}, socket) do
    {:noreply, assign(socket, hero_tab: tab)}
  end

  def handle_event("toggle-battle-details", _, socket) do
    {:noreply, assign(socket, show_battle_details: !socket.assigns.show_battle_details)}
  end

  def handle_event("clear-lineup", _, socket), do: {:noreply, assign(socket, picked_heroes: [])}

  def handle_event("source-page", %{"source" => source, "direction" => direction}, socket)
      when source in ["teams", "heroes"] and direction in ["previous", "next"] do
    {key, entries, size} =
      if source == "teams",
        do: {:teams_page, socket.assigns.teams, 6},
        else: {:heroes_page, socket.assigns.trained_heroes, 12}

    delta = if direction == "next", do: 1, else: -1
    page = (socket.assigns[key] + delta) |> max(0) |> min(max(0, div(length(entries) - 1, size)))
    {:noreply, assign(socket, key, page)}
  end

  def handle_event("repeat", _, %{assigns: %{latest_match: match}} = socket) when not is_nil(match) do
    ids = match.player_picks |> Enum.take(socket.assigns.match.team_size) |> Enum.map(& &1.id)

    if Moba.Game.Matches.valid_picks?(socket.assigns.match, socket.assigns.current_player, ids),
      do: {:noreply, assign(socket, picked_heroes: Enum.take(match.player_picks, socket.assigns.match.team_size))},
      else: {:noreply, socket}
  end

  def handle_event("repeat", _, socket), do: {:noreply, socket}

  def handle_event("pick-hero", %{"id" => id} = params, %{assigns: %{starting: false}} = socket) do
    %{match: match, current_player: player, picked_heroes: heroes} = socket.assigns

    with true <- Map.get(params, "lineup_id", match.id) == match.id && length(heroes) < match.team_size,
         {:ok, hero_id} <- Ecto.Type.cast(:integer, id),
         false <- Enum.any?(heroes, &(&1.id == hero_id)),
         [hero] <- Game.Matches.selectable_heroes(match, player, [hero_id]) do
      {:noreply, assign(socket, picked_heroes: heroes ++ [hero])}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick-hero", _, socket), do: {:noreply, socket}

  def handle_event("unpick-hero", %{"id" => id}, %{assigns: %{picked_heroes: heroes}} = socket) do
    hero = Enum.find(heroes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, picked_heroes: heroes -- [hero])}
  end

  def handle_event("pick-team", %{"id" => id}, %{assigns: %{teams: teams}} = socket) do
    case Enum.find(teams, &(&1.id == String.to_integer(id))) do
      nil ->
        {:noreply, socket}

      team ->
        ids = team.pick_ids |> Enum.uniq() |> Enum.take(socket.assigns.match.team_size)

        eligible =
          Moba.Game.Matches.selectable_heroes(socket.assigns.match, socket.assigns.current_player, ids)
          |> Map.new(&{&1.id, &1})

        picks = Enum.flat_map(ids, fn id -> if hero = eligible[id], do: [hero], else: [] end)

        if picks == [] do
          {:noreply,
           put_flash(socket, :error, "This team has no available heroes. Update the team or pick heroes individually.")}
        else
          Game.update_team!(team, %{used_count: team.used_count + 1})
          socket = assign(socket, picked_heroes: picks)

          socket =
            if length(picks) < length(ids),
              do:
                put_flash(
                  socket,
                  :info,
                  "Some team heroes are no longer available. Choose replacements for the open slots."
                ),
              else: socket

          {:noreply, socket}
        end
    end
  end

  def handle_event("move-up", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), -1, socket)}
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), 1, socket)}
  end

  def handle_event("reorder-lineup", %{"lineup_id" => id, "hero_ids" => ids}, socket) do
    %{match: match, picked_heroes: picks, starting: starting} = socket.assigns
    heroes = Map.new(picks, &{&1.id, &1})

    if !starting && id === match.id && is_list(ids) && length(ids) == map_size(heroes) &&
         Enum.sort(ids) === Enum.sort(Map.keys(heroes)) do
      {:noreply, assign(socket, picked_heroes: Enum.map(ids, &Map.fetch!(heroes, &1)))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start", _, %{assigns: %{starting: true}} = socket), do: {:noreply, socket}

  def handle_event("start", _, %{assigns: %{match: match, picked_heroes: picked_heroes}} = socket) do
    ids = picked_heroes |> Enum.take(socket.assigns.match.team_size) |> Enum.map(& &1.id)
    player = socket.assigns.current_player

    task =
      Task.Supervisor.async_nolink(Moba.TaskSupervisor, fn ->
        Game.start_match(match, player, ids, interactive: true)
      end)

    {:noreply, assign(socket, tick: 0, starting: true, match_task_ref: task.ref)}
  end

  def handle_info(_, %{assigns: %{training_record: record}} = socket) when not is_nil(record),
    do: {:noreply, socket}

  def handle_info(:tick, %{assigns: %{tick: tick, match: %{id: match_id, winner_id: winner_id}}} = socket)
      when is_nil(winner_id) and tick < @max_tick do
    schedule_tick()
    {:noreply, socket_init(match_id, tick + 1, socket)}
  end

  def handle_info(:tick, %{assigns: %{tick: tick, battles: battles}} = socket) when tick < length(battles) do
    schedule_tick()
    {:noreply, assign(socket, tick: tick + 1)}
  end

  def handle_info(:tick, socket), do: {:noreply, socket}

  def handle_info({:DOWN, ref, :process, _, _reason}, %{assigns: %{match_task_ref: ref}} = socket) do
    socket = socket_init(socket.assigns.match.id, @max_tick, assign(socket, starting: false, match_task_ref: nil))

    socket =
      if socket.assigns.match.phase == "scored" do
        socket
      else
        put_flash(socket, :error, "The match could not start. Please try again.")
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _, _, _, _}, socket), do: {:noreply, socket}

  def handle_info({ref, {:error, _}}, %{assigns: %{match_task_ref: ref}} = socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    socket = assign(socket, starting: false, match_task_ref: nil)
    {:noreply, socket_init(socket.assigns.match.id, @max_tick, socket)}
  end

  def handle_info({ref, {:ok, match}}, %{assigns: %{match_task_ref: ref}} = socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    socket = assign(socket, starting: false, match_task_ref: nil)

    if match.interactive do
      battle = Engine.latest_match_battle(match.id)
      {:noreply, push_navigate(socket, to: ~p"/battles/#{battle.id}")}
    else
      {:noreply, socket_init(match.id, socket.assigns.tick, socket)}
    end
  end

  def handle_info({ref, _result}, socket) when is_reference(ref), do: {:noreply, socket}

  def render(%{training_record: record} = assigns) when not is_nil(record),
    do: MobaWeb.V2.Components.TrainingBattle.page(assigns)

  def render(%{match: %{interactive: true, phase: phase}} = assigns) when not is_nil(phase),
    do: MobaWeb.V2.Components.ArenaBattle.page(Map.put(assigns, :arena_match_id, assigns.match.id))

  def render(assigns), do: show(assigns)

  defp socket_init(match_id, tick, %{assigns: %{current_player: player}} = socket) do
    match = Game.get_match!(match_id)
    latest_match = Game.latest_manual_match(player)
    battles = Engine.list_match_battles(match_id)
    teams = Game.list_teams(player) |> Enum.sort_by(&{-&1.used_count, -&1.id})
    trained_heroes = Game.trained_pvp_heroes(player.id, [], 200)
    hero_tab = if length(teams) > 0, do: "teams", else: "trained"

    assign(socket,
      sidebar_code: "arena",
      channel: "match-#{match_id}",
      match: match,
      match_task_ref: Map.get(socket.assigns, :match_task_ref),
      battles: battles,
      tick: tick,
      trained_heroes: trained_heroes,
      picked_heroes: Enum.filter(match.player_picks, & &1),
      generated_heroes: available_heroes(match, player, trained_heroes),
      hero_tab: hero_tab,
      latest_match: latest_match,
      teams: teams,
      teams_page: Map.get(socket.assigns, :teams_page, 0),
      heroes_page: Map.get(socket.assigns, :heroes_page, 0),
      starting: Map.get(socket.assigns, :starting, false) && is_nil(match.phase),
      show_battle_details: Map.get(socket.assigns, :show_battle_details, false),
      hide_footer: true
    )
  end

  defp available_heroes(match, %{pvp_tier: 0}, _trained_heroes), do: match.generated_picks

  defp available_heroes(_match, _player, trained_heroes) do
    Moba.pve_ranking_available()
    |> Enum.reject(&Enum.member?(trained_heroes, &1))
    |> Enum.take(10)
  end

  defp move(hero_id, slide, %{assigns: %{picked_heroes: picked_heroes}} = socket) do
    index = Enum.find_index(picked_heroes, &(&1.id == hero_id))

    if is_nil(index) or index + slide < 0 or index + slide >= length(picked_heroes) do
      socket
    else
      assign(socket, picked_heroes: Enum.slide(picked_heroes, index, index + slide))
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_timeout)

  defp eliminated?(hero, player, battles) do
    Enum.any?(battles, fn battle ->
      battler = turn_hero_for(battle, player)
      battler.hero_id == hero.id && battler.current_hp <= 0
    end)
  end

  defp player_pick(
         %{
           attacker_id: attacker_id,
           defender_id: defender_id,
           attacker_player_id: attacker_player_id,
           defender_player_id: defender_player_id
         },
         %{player_id: player_id, player_picks: picks}
       ) do
    Enum.find(
      picks,
      &((&1.id == attacker_id && attacker_player_id == player_id) ||
          (&1.id == defender_id && defender_player_id == player_id))
    )
  end

  defp opponent_pick(
         %{
           attacker_id: attacker_id,
           defender_id: defender_id,
           attacker_player_id: attacker_player_id,
           defender_player_id: defender_player_id
         },
         %{opponent_id: opponent_id, opponent_picks: picks}
       ) do
    Enum.find(
      picks,
      &((&1.id == attacker_id && attacker_player_id == opponent_id) ||
          (&1.id == defender_id && defender_player_id == opponent_id))
    )
  end

  defp turn_hero_for(battle, player) do
    turn = List.last(battle.turns)
    if turn.attacker.player_id == player.id, do: turn.attacker, else: turn.defender
  end
end
