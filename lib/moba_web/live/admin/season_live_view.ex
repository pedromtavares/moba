defmodule MobaWeb.Admin.SeasonLiveView do
  use MobaWeb, :live_view

  alias Moba.Admin
  alias MobaWeb.PlayerView

  def mount(_, _, socket) do
    if connected?(socket), do: MobaWeb.subscribe("admin")

    {:ok, base_assigns(socket)}
  end

  def handle_info({"server", _}, socket) do
    {:noreply, base_assigns(socket)}
  end

  def handle_event("filter", _, %{assigns: %{filter: filter}} = socket) do
    new_filter = if filter == :weekly, do: :daily, else: :weekly
    {:noreply, assign(socket, filter: new_filter) |> base_assigns()}
  end

  def handle_event("stats-filter", params, socket) do
    with filter = Map.get(params, "type") do
      {:noreply, assign(socket, stats_filter: filter) |> base_assigns()}
    end
  end

  defp base_assigns(socket) do
    data = Admin.get_server_data()

    filter = socket.assigns[:filter] || :weekly
    stats_filter = socket.assigns[:stats_filter] || "elite"

    assign(socket,
      players: data.players,
      guests: data.guests,
      filter: filter,
      user_stats: data.user_stats[filter],
      stats_filter: stats_filter,
      match_stats: data.match_stats[stats_filter],
      duels: data.duels,
      last_updated: Timex.now()
    )
  end

  def xp_farm_percentage(%{total_xp_farm: xp_farm, total_gold_farm: gold_farm}) do
    total = xp_farm + gold_farm
    if total > 0, do: div(xp_farm * 100, total), else: 100
  end

  def gold_farm_percentage(hero), do: 100 - xp_farm_percentage(hero)

  def bottom_performing(stats, key) do
    limit = if key == :items, do: 6, else: 10

    mapped_stats(stats, key)
    |> Enum.sort_by(fn {_record, {_winrate, _, diff}} -> diff end)
    |> Enum.take(limit)
  end

  def top_performing(stats, key) do
    limit = if key == :items, do: 6, else: 10

    mapped_stats(stats, key)
    |> Enum.sort_by(fn {_record, {_winrate, _, diff}} -> diff * -1 end)
    |> Enum.take(limit)
  end

  def winrate_class(diff, "pvp") when diff > 4 or diff < -4, do: "text-danger"
  def winrate_class(diff, "plebs") when diff > 4 or diff < -4, do: "text-danger"
  def winrate_class(diff, "elite") when diff > 8 or diff < -8, do: "text-danger"
  def winrate_class(diff, _) when diff > 10 or diff < -10, do: "text-danger"
  def winrate_class(diff, "pvp") when diff > 2 or diff < -2, do: "text-warning"
  def winrate_class(diff, "plebs") when diff > 2 or diff < -2, do: "text-warning"
  def winrate_class(diff, "elite") when diff > 4 or diff < -4, do: "text-warning"
  def winrate_class(diff, _) when diff > 5 or diff < -5, do: "text-warning"
  def winrate_class(_, _), do: "text-success"

  defp mapped_stats(stats, key) do
    data = stats[key]
    average = stats[:winrate]

    Enum.map(data, fn {record, {winrate, total}} ->
      {record, {winrate, total, winrate - average}}
    end)
  end

  defp arena_stats(assigns) do
    ~H"""
    <table class="table-dark table border m-0">
      <%= for {record, {winrate, total, diff}} <- @records do %>
        <tr id={"#{record.code}-stats-row"}>
          <td>
            <img src={GH.image_url(record)} class="img-border-xs" style="height: 50px" />
          </td>
          <td>
            <h4><%= record.name %></h4>
          </td>
          <td>
            <h3 class={"#{winrate_class(diff, @stats_filter)} text-center m-0"}>
              <%= round(winrate) %>% <br /><small><em>(<%= total %>)</em></small>
            </h3>
          </td>
        </tr>
      <% end %>
    </table>
    """
  end

  defp guest(assigns) do
    ~H"""
    <div class="col-md-1 col-2" id={"guest-#{@player.id}"}>
      <div class="card-box p-1">
        <img src={GH.image_url(@player.current_pve_hero.avatar)} style="width: 100%" class="img-border-xs" /><br />
        <h5 class="text-white text-center">
          <img src={"/images/league/#{@player.current_pve_hero.league_tier}.png"} style="width: 20px;" /> Lv
          <span class={if @player.current_pve_hero.pve_state == "dead", do: "text-muted"}>
            <%= @player.current_pve_hero.level %>
          </span>
          (<%= length(@player.hero_collection) %>)
        </h5>
        <div>
          <%= for skill <- @player.current_pve_hero.skills do %>
            <%= img_tag(GH.image_url(skill), style: "width: 20%") %>
          <% end %>
        </div>
        <div>
          <%= for item <- @player.current_pve_hero.items do %>
            <%= img_tag(GH.image_url(item), style: "width: 20%") %>
          <% end %>
        </div>
        <div class="progress mb-1 mt-2 margin-auto" style="max-width: 150px">
          <div class="progress-bar" style={"width: #{xp_farm_percentage(@player.current_pve_hero)}%"}>
            <%= xp_farm_percentage(@player.current_pve_hero) %>
          </div>
          <div class="progress-bar bg-warning" style={"width: #{gold_farm_percentage(@player.current_pve_hero)}%"}>
            <%= gold_farm_percentage(@player.current_pve_hero) %>
          </div>
        </div>
        <p class="text-center m-0">
          <span class="text-muted">
            <%= @player.current_pve_hero.pve_total_turns + @player.current_pve_hero.pve_current_turns %>t
          </span>
          | <span class="text-primary"><%= @player.tutorial_step %></span>
          |
          <span class="text-success">
            <%= @player.current_pve_hero.total_gold_farm + @player.current_pve_hero.total_xp_farm %>
          </span>
          <br />
          <small class="text-dark font-italic">
            <%= @player.inserted_at |> Timex.format("{relative}", :relative) |> elem(1) %>
          </small>
        </p>
      </div>
    </div>
    """
  end

  defp player_row(assigns) do
    ~H"""
    <tr id={"user-#{@player.id}"}>
      <td class="text-center">
        <.link navigate={~p"/player/#{@player.id}"} class="text-white">
          <img
            src={"/images/pve/#{@player.pve_tier}.png"}
            class={"rank-shadow-#{PlayerView.shadow_rank(@player)}"}
            style="max-height:  50px"
          />
          <br />
          <span class={"text-white rank-shadow-#{PlayerView.shadow_rank(@player)}"}><%= @player.user.username %></span>
          <span class="badge badge-pill badge-light-success"><%= @player.hero_count %></span>
          <span class="badge badge-pill badge-light-dark"><%= @player.user.shard_count %></span>
        </.link>
        <br />
        <small class="text-dark font-italic ">
          D#<%= @player.ranking %> - S#<%= @player.season_ranking %> - BS <%= @player.best_immortal_streak %> - CS <%= @player.current_immortal_streak %>
          <br /> Online <%= @player.user.last_online_at |> Timex.format("{relative}", :relative) |> elem(1) %>
          <br /> Registered <%= @player.user.inserted_at |> Timex.format("{relative}", :relative) |> elem(1) %>
        </small>
      </td>
      <%= for hero <- @player.latest_heroes do %>
        <td class={"text-center #{if hero.id == @player.current_pve_hero_id, do: "border"}"}>
          <img src={"#{GH.image_url(hero.avatar)}"} style="width: 100px;" class="img-border-xs" /><br />
          <h5 class="mb-0 text-center">
            <img src={"/images/league/#{hero.league_tier}.png"} style="width: 20px;" />
            <.link navigate={~p"/hero/#{hero}"} class="text-white">
              Lv <span class={if hero.pve_state == "dead", do: "text-muted"}><%= hero.level %></span>
              <%= if hero.pve_ranking do %>
                <span class="text-success">#<%= hero.pve_ranking %></span>
              <% end %>
            </.link>
          </h5>
          <div class="progress mb-1 mt-2 margin-auto" style="max-width: 150px">
            <div class="progress-bar" role="progressbar" style={"width: #{xp_farm_percentage(hero)}%"}>
              <%= xp_farm_percentage(hero) %>
            </div>
            <div class="progress-bar bg-warning" style={"width: #{gold_farm_percentage(hero)}%"}>
              <%= gold_farm_percentage(hero) %>
            </div>
          </div>
          <%= if hero.finished_at do %>
            <span class="text-muted"><%= hero.finished_at |> Timex.format("{relative}", :relative) |> elem(1) %></span>
          <% else %>
            <span class="text-muted"><%= hero.pve_total_turns + hero.pve_current_turns %>t</span>
          <% end %>
          |
          <span class="text-info">
            <%= trunc(MobaWeb.BattleView.league_success_rate(hero)) %>%
          </span>
          |
          <span class="text-center text-success">
            <span class="text-danger"><%= hero.buybacks %></span>
          </span>
          | <span class="text-success"><%= hero.total_gold_farm + hero.total_xp_farm %></span>
        </td>
      <% end %>
    </tr>
    """
  end
end
