defmodule MobaWeb.V2.TeamLive do
  use MobaWeb, :v2_live_view
  on_mount MobaWeb.V2.Hooks.TeamAccess
  alias Moba.Game.TeamRuns
  alias Phoenix.LiveView.JS
  import MobaWeb.CoreComponents, only: [icon: 1]
  import MobaWeb.V2.Components.ProgressionComponents, only: [training_completion: 1, progression_rewards: 1]
  import MobaWeb.V2.Components.TrainingComponents, only: [perfect_indicator: 1]

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope
    team = TeamRuns.profile!(scope, id)
    show_completion = recent_completion?(scope, team)

    completed_quest =
      if show_completion && team.league_tier >= Moba.platinum_league_tier() && team.player.pve_progression do
        Game.last_completed_quest(team)
      end

    {:noreply,
     assign(socket,
       team: team,
       show_completion: show_completion,
       completed_quest: completed_quest,
       sidebar_code: "profile",
       team_ranking: TeamRuns.ranking(team.id),
       xp_farm: Enum.sum(Enum.map(team.heroes, & &1.total_xp_farm)),
       gold_farm: Enum.sum(Enum.map(team.heroes, & &1.total_gold_farm))
     )}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp recent_completion?(%{player_id: player_id} = scope, %{id: id, player_id: player_id} = team) do
    (is_nil(scope.user) || DateTime.diff(DateTime.utc_now(), team.finished_at) < 86_400) &&
      match?(%{id: ^id}, TeamRuns.latest(scope, player_id))
  end

  defp recent_completion?(_scope, _team), do: false

  defp select_hero(id) do
    JS.add_class("d-none", to: "[data-team-profile-card]")
    |> JS.remove_class("d-none", to: "#team-profile-hero-#{id}")
    |> JS.set_attribute({"aria-selected", "false"}, to: ".team-profile-tab")
    |> JS.set_attribute({"aria-selected", "true"}, to: "#team-profile-tab-#{id}")
  end

  defp tier_class(tier, current) do
    cond do
      tier == current -> "current-tier"
      tier < current -> "previous-tier"
      true -> "next-tier"
    end
  end
end
