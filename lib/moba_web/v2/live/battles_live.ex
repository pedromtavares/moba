defmodule MobaWeb.V2.BattlesLive do
  use MobaWeb, :v2_live_view
  on_mount MobaWeb.V2.Hooks.TeamAccess
  import MobaWeb.CoreComponents, only: [icon: 1]

  alias Moba.Game.{TeamRuns, TrainingEncounters}

  embed_templates "battles_live/*"

  def mount(%{"run" => param}, _, socket) do
    %{current_player: player, current_scope: scope} = socket.assigns

    with param when is_binary(param) <- param,
         {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(param),
         %{player_id: player_id} = run when player_id == player.id <- TeamRuns.get(scope, id) do
      {:ok, load_team(socket, run)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That team’s battle log is unavailable.")
         |> push_navigate(to: ~p"/base")}
    end
  end

  def mount(_, _, %{assigns: %{current_hero: nil}} = socket) do
    %{current_player: player, current_scope: scope} = socket.assigns

    case TeamRuns.active(scope, player.id) do
      nil -> {:ok, push_navigate(socket, to: ~p"/base")}
      run -> {:ok, load_team(socket, run)}
    end
  end

  def mount(_, _, socket) do
    hero = socket.assigns.current_hero
    battles = Enum.map(Engine.list_battles(hero, "pve"), &solo_entry(&1, hero.id))
    challenges = Enum.map(Engine.list_battles(hero, "league"), &solo_entry(&1, hero.id))

    {:ok,
     assign(socket,
       history_tab: "ganks",
       subject: hero.name,
       league_tier: hero.league_tier,
       return_path: ~p"/training",
       sections: sections(battles, challenges, hero.wins, hero.losses, hero.league_attempts, hero.league_successes)
     )}
  end

  def handle_event("history-tab", %{"tab" => tab}, socket) when tab in ["ganks", "league"] do
    {:noreply, assign(socket, :history_tab, tab)}
  end

  defp load_team(socket, run) do
    {battles, challenges} =
      socket.assigns.current_scope
      |> TeamRuns.encounters(run.id)
      |> Enum.reverse()
      |> Enum.split_with(&(&1.kind == :farm))

    assign(socket,
      history_tab: "ganks",
      subject: run.name || "Team training",
      league_tier: run.league_tier,
      return_path: ~p"/training?#{[run: run.id]}",
      sections:
        sections(
          Enum.map(battles, &team_entry/1),
          Enum.map(challenges, &team_entry/1),
          Enum.count(battles, &(&1[:winner] == :radiant)),
          Enum.count(battles, &(&1[:winner] == :dire)),
          length(challenges),
          Enum.count(challenges, &(&1[:winner] == :radiant))
        )
    )
  end

  defp sections(battles, challenges, wins, losses, attempts, successes) do
    [
      %{
        id: "ganks",
        title: "Training Battles",
        entries: battles,
        summary: [{"Wins / Losses", {wins, losses}}, {"Win rate", rate(wins, wins + losses)}]
      },
      %{
        id: "league",
        title: "League Challenges",
        entries: challenges,
        summary: [{"Attempts", attempts}, {"Success rate", rate(successes, attempts)}]
      }
    ]
  end

  defp rate(_, 0), do: "0%"
  defp rate(wins, total), do: "#{round(wins * 100 / total)}%"

  defp solo_entry(battle, hero_id) do
    {opponent, snapshot} =
      if battle.attacker_id == hero_id,
        do: {battle.defender, battle.defender_snapshot},
        else: {battle.attacker, battle.attacker_snapshot}

    result =
      cond do
        battle.winner_id == hero_id -> "WIN"
        battle.type == "pve" && is_nil(battle.winner_id) -> "TIE"
        true -> "LOSS"
      end

    level = (snapshot && snapshot.level) || opponent.level
    avatar = opponent.avatar
    detail = if opponent.name == avatar.name, do: "Lv #{level}", else: "Lv #{level} · #{avatar.name}"

    %{
      id: "battle-#{battle.id}",
      replay_id: "replay-battle-#{battle.id}",
      path: ~p"/battles/#{battle.id}",
      name: opponent.name,
      avatar: avatar,
      detail: detail,
      inserted_at: battle.inserted_at,
      result: result,
      difficulty: difficulty_label(battle.difficulty),
      xp: battle.rewards && battle.rewards.total_xp,
      gold: battle.rewards && battle.rewards.total_gold,
      progress: league_progress(battle, result)
    }
  end

  defp team_entry(encounter) do
    opponent = encounter.opponent
    fighter = encounter.fighter

    result =
      case {encounter.status, encounter[:winner]} do
        {:pending, _} -> "IN PROGRESS"
        {:finished, :radiant} -> "WIN"
        {:finished, :dire} -> "LOSS"
        {:finished, :draw} -> "TIE"
        _ -> nil
      end

    %{
      id: "encounter-#{encounter.id}",
      replay_id: "team-replay-#{encounter.id}",
      path: TrainingEncounters.path(encounter),
      name: if(encounter.kind == :farm && opponent, do: opponent.name, else: encounter.label),
      avatar: opponent && opponent.avatar,
      detail:
        if(encounter.kind == :farm && fighter,
          do: "Turn #{encounter.turn} · #{fighter.name}",
          else: "Turn #{encounter.turn}"
        ),
      inserted_at: encounter.inserted_at,
      result: result,
      difficulty: if(encounter.kind == :farm, do: encounter.label),
      xp: get_in(encounter, [:reward_totals, :xp]),
      gold: get_in(encounter, [:reward_totals, :gold]),
      progress: nil
    }
  end

  defp difficulty_label("weak"), do: "Easy"
  defp difficulty_label("moderate"), do: "Medium"
  defp difficulty_label("strong"), do: "Hard"
  defp difficulty_label(_), do: nil

  defp league_progress(%{type: "league", attacker_snapshot: %{league_step: 0, league_tier: tier}}, "WIN")
       when is_integer(tier),
       do: {:promotion, tier}

  defp league_progress(%{type: "league", attacker_snapshot: %{previous_league_step: step}}, result)
       when is_integer(step),
       do: {if(result == "WIN", do: :step_win, else: :step_loss), step}

  defp league_progress(_, _), do: nil

  defp relative_time(inserted_at), do: Timex.format!(inserted_at, "{relative}", :relative)
end
