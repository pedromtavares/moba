defmodule MobaWeb.V2.BattlesLive do
  use MobaWeb, :v2_live_view

  embed_templates "battles_live/*"

  def mount(_, _, socket) do
    {:ok, socket |> maybe_redirect() |> socket_init()}
  end

  def handle_event("redirect", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/battles/#{id}")}
  end

  defp maybe_redirect(%{assigns: %{current_hero: nil}} = socket) do
    redirect(socket, to: "/base")
  end

  defp maybe_redirect(socket), do: socket

  defp socket_init(%{assigns: %{current_hero: hero}} = socket) when not is_nil(hero) do
    league_battles = Engine.list_battles(hero, "league")
    pve_battles = Engine.list_battles(hero, "pve")

    assign(socket,
      league_battles: league_battles,
      pve_battles: pve_battles,
      sidebar_code: "training"
    )
  end

  defp socket_init(socket), do: socket

  defp opponent_for(battle, current_hero_id) do
    if current_hero_id == battle.attacker_id, do: battle.defender, else: battle.attacker
  end

  defp result_badge_label(%{type: "pve", winner: winner}, current_hero_id) do
    cond do
      is_nil(winner) -> "TIE"
      winner.id == current_hero_id -> "WIN"
      true -> "LOSS"
    end
  end

  defp result_badge_label(%{winner: winner}, current_hero_id) do
    if winner && winner.id == current_hero_id, do: "WIN", else: "LOSS"
  end

  defp result_badge_class(%{type: "pve", winner: winner}, current_hero_id) do
    cond do
      is_nil(winner) -> "badge badge-light-warning"
      winner.id == current_hero_id -> "badge badge-light-success"
      true -> "badge badge-light-dark"
    end
  end

  defp result_badge_class(%{winner: winner}, current_hero_id) do
    if winner && winner.id == current_hero_id, do: "badge badge-light-success", else: "badge badge-light-danger"
  end

  defp difficulty_badge(nil), do: nil
  defp difficulty_badge("weak"), do: {"EASY", "badge badge-light-success"}
  defp difficulty_badge("moderate"), do: {"MEDIUM", "badge badge-light-primary"}
  defp difficulty_badge("strong"), do: {"HARD", "badge badge-light-danger"}
  defp difficulty_badge(_), do: nil

  defp reward_badges(battle, current_hero_id) do
    rewards = battle.rewards

    points =
      if current_hero_id == battle.attacker_id do
        rewards.attacker_pvp_points
      else
        rewards.defender_pvp_points
      end

    %{
      xp: rewards.total_xp,
      gold: rewards.total_gold,
      pvp_points: if(battle.type == "pvp", do: points, else: nil)
    }
  end

  defp pvp_badge_class(points) when points > 0, do: "badge badge-light-primary"
  defp pvp_badge_class(_), do: "badge badge-light-dark"

  defp relative_time(%{inserted_at: inserted_at}) do
    Timex.format!(inserted_at, "{relative}", :relative)
  end

  defp league_step_result(%{type: "league"} = battle, current_hero_id) do
    winner = battle.winner && battle.winner.id == current_hero_id

    if winner do
      if battle.attacker_snapshot.league_step == 0 do
        {:rank, battle.attacker_snapshot.league_tier}
      else
        {:step_win, battle.attacker_snapshot.previous_league_step}
      end
    else
      {:step_loss, battle.attacker_snapshot.previous_league_step}
    end
  end

  defp league_step_result(_battle, _current_hero_id), do: nil

  defp max_available_league(%{pve_tier: pve_tier, league_attempts: attempts} = hero) do
    max = Moba.max_available_league(pve_tier)

    if max != Moba.max_league_tier() || attempts == 0 || league_success_rate(hero) >= 100 do
      max
    else
      max - 1
    end
  end

  defp turn_percentage(%{pve_current_turns: turns}) do
    (5 - turns) * 100 / 5
  end

  defp expert_hero?(%{pve_tier: tier}) when tier >= 4, do: true
  defp expert_hero?(_), do: false

  defp elapsed_time(%{inserted_at: inserted_at}) do
    Timex.diff(Timex.now(), inserted_at, :minutes)
  end

  defp win_rate(%{wins: wins, losses: losses}) do
    total = wins + losses
    if total == 0, do: 0, else: round(wins * 100 / total)
  end

  defp league_success_rate(%{league_attempts: attempts, league_successes: successes}) when attempts > 0 do
    round(successes * 100 / attempts)
  end

  defp league_success_rate(_), do: 0

  attr :battle, :map, required: true
  attr :current_hero, :map, required: true

  defp battle_row(assigns) do
    ~H"""
    <% opponent = opponent_for(@battle, @current_hero.id) %>
    <% difficulty = difficulty_badge(@battle.difficulty) %>
    <% rewards = @battle.rewards && reward_badges(@battle, @current_hero.id) %>
    <% league_result = league_step_result(@battle, @current_hero.id) %>

    <tr
      id={"battle-#{@battle.id}"}
      class="battle-row"
      phx-click="redirect"
      phx-value-id={@battle.id}
      phx-hook="Loading"
    >
      <td>
        <span class={result_badge_class(@battle, @current_hero.id)}>
          {result_badge_label(@battle, @current_hero.id)}
        </span>
      </td>
      <td>
        <img src={GH.image_url(opponent.avatar)} class="avatar img-border-xs" />
        <br />
        <span class="text-dark font-italic">{opponent.name}</span>
      </td>
      <td>
        <%= if difficulty do %>
          <span class={elem(difficulty, 1)}>{elem(difficulty, 0)}</span>
          <br />
        <% end %>
        <%= if rewards do %>
          <div>
            <%= if rewards.xp > 0 do %>
              <span class="badge badge-light-info">{rewards.xp} XP</span>
            <% end %>
            <%= if rewards.gold > 0 do %>
              <span class="badge badge-light-warning">{rewards.gold}g</span>
            <% end %>
            <%= if rewards.pvp_points do %>
              <span class={pvp_badge_class(rewards.pvp_points)}>{rewards.pvp_points} Points</span>
            <% end %>
          </div>
        <% end %>
        <%= if league_result do %>
          <ul class="nav nav-pills nav-justified form-wizard-header flex-center">
            <%= case league_result do %>
              <% {:rank, tier} -> %>
                <img src={"/images/league/#{tier}.png"} class="mr-1 league-rank" />
              <% {:step_win, step} -> %>
                <li class="nav-item">
                  <a href="javascript:;" class="nav-link success">
                    <span class="number"><i class="fa fa-check" aria-hidden="true"></i></span>
                    <span class="d-none d-sm-inline">{step}</span>
                  </a>
                </li>
              <% {:step_loss, step} -> %>
                <li class="nav-item">
                  <a href="javascript:;" class="nav-link failure">
                    <span class="number"><i class="fa fa-times" aria-hidden="true"></i></span>
                    <span class="d-none d-sm-inline">{step}</span>
                  </a>
                </li>
            <% end %>
          </ul>
        <% end %>
      </td>
      <td>
        <span class="loading-text">{relative_time(@battle)}</span>
      </td>
    </tr>
    """
  end
end
