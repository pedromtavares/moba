defmodule MobaWeb.CommunityView do
  use MobaWeb, :view

  alias MobaWeb.PlayerView

  def formatted_body(%{body: body}) do
    body
    |> text_to_html()
    |> safe_to_string()
    |> String.replace(
      ~r/https:\/\/browsermoba.com\/battles\/([0-9]+)/,
      "<a href='/battles/\\1' class='text-primary'>Battle #\\1</span>"
    )
    |> raw()
  end

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
            <h3 class={"#{winrate_class(diff, @match_filter)} text-center m-0"}>
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
      <div class="card">
        <div
          class="card-header border p-0"
          style="background: rgba(0,0,0, 0.1)"
          data-toggle={if @is_admin, do: "tooltip"}
          title={
            if @is_admin,
              do:
                "Created #{@player.inserted_at |> Timex.format("{relative}", :relative) |> elem(1)}.<br/>Total heroes: #{length(@player.hero_collection)}"
          }
        >
          <h5 class="f-rpg"><%= if @current, do: "YOU", else: "GUEST" %></h5>
        </div>
        <div class="card-body p-1 border" style="border-radius: 0">
          <img src={GH.image_url(@player.current_pve_hero.avatar)} style="width: 100%" class="img-border-xs" /><br />
          <h5 class="text-white text-center">
            <img src={"/images/league/#{@player.current_pve_hero.league_tier}.png"} style="width: 20px;" /> Lv
            <span class={if @player.current_pve_hero.pve_state == "dead", do: "text-muted"}>
              <%= @player.current_pve_hero.level %>
            </span>
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
        </div>
      </div>
    </div>
    """
  end

  defp player_row(assigns) do
    ~H"""
    <tr id={"user-#{@player.id}"} style={if @current, do: "background: rgba(255,255,255, 0.02)"}>
      <td class="text-center cursor-pointer border" phx-click={JS.navigate(~p"/player/#{@player.id}")}>
        <span
          class="text-white"
          data-toggle={if @is_admin, do: "tooltip"}
          title={
            if @is_admin,
              do: "Online #{@player.user.last_online_at |> Timex.format("{relative}", :relative) |> elem(1)}<br/>
                Registered #{@player.user.inserted_at |> Timex.format("{relative}", :relative) |> elem(1)}<br/>
                Total heroes: #{@player.hero_count}"
          }
        >
          <img
            src={"/images/pve/#{@player.pve_tier}.png"}
            class={"rank-shadow-#{PlayerView.shadow_rank(@player)}"}
            style="max-height: 50px;"
          />
          <br />
          <h5 class={"text-white rank-shadow-#{PlayerView.shadow_rank(@player)} mb-1"}><%= @player.user.username %></h5>
          <%= status_pill(assigns) %>
        </span>
      </td>
      <td class="text-center cursor-pointer border" phx-click={JS.navigate(~p"/player/#{@player.id}")}>
        <h2 class="f-rpg text-danger">
          <%= if @player.ranking do %>
            #<%= @player.ranking %>
          <% else %>
            ?
          <% end %>
        </h2>
        <h4 class={"rank-shadow-#{PlayerView.shadow_rank(@player)} f-rpg"}><%= MobaWeb.ArenaView.tier_label(@player) %></h4>
      </td>
      <td>
        <div class="d-flex justify-content-start">
          <%= for hero <- @player.latest_heroes do %>
            <div class="col-2">
              <.link navigate={~p"/hero/#{hero}"}>
                <img
                  src={"#{GH.image_url(hero.avatar)}"}
                  style={"width: 100px; #{if Game.max_farm?(hero), do: "border: 1px solid red; border-radius:2px"}"}
                  class="img-border-xs"
                /><br />
                <h5 class="mb-0 text-center">
                  <img src={"/images/league/#{hero.league_tier}.png"} style="width: 20px;" />
                  <span class="text-white">
                    Lv <span class={if hero.pve_state == "dead", do: "text-muted"}><%= hero.level %></span>
                    <%= if hero.pve_ranking do %>
                      <span class="text-success">#<%= hero.pve_ranking %></span>
                    <% end %>
                  </span>
                </h5>
                <%= if hero.finished_at do %>
                  <span
                    class="text-center text-muted"
                    data-toggle={if @is_admin, do: "tooltip"}
                    title={if @is_admin, do: hero.finished_at |> Timex.format("{relative}", :relative) |> elem(1)}
                  >
                    Trained in <%= GH.finished_time(hero) %> min
                  </span>
                <% else %>
                  <span class="text-center text-muted"><%= hero.pve_total_turns %> turns left</span>
                <% end %>
              </.link>
            </div>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  defp status_pill(assigns) do
    last_online_at = assigns.player.user.last_online_at
    time_diff = Timex.diff(Timex.now(), last_online_at, :hours)

    cond do
      time_diff < 1 ->
        ~H"""
        <span class="badge badge-pill badge-light-success">Online</span>
        """

      time_diff < 24 ->
        ~H"""
        <span class="badge badge-pill badge-light-warning">Away</span>
        """

      true ->
        ~H"""
        <span class="badge badge-pill badge-light-danger">Offline</span>
        """
    end
  end
end
