defmodule MobaWeb.Admin.MatchLiveView do
  use MobaWeb, :live_view

  alias Moba.{Game, Admin}

  def mount(_, %{"match_id" => match_id} = session, socket) do
    if connected?(socket), do: MobaWeb.subscribe("admin")

    match = if match_id == "current", do: Game.current_match(), else: Admin.get_match!(match_id)
    matches = Admin.list_recent_matches()

    {:ok, assign(socket, match: match, matches: matches) |> set_vars()}
  end

  def handle_info({"server", _}, socket) do
    {:noreply, set_vars(socket)}
  end

  def render(assigns) do
    MobaWeb.Admin.MatchView.render("show.html", assigns)
  end

  defp set_vars(socket) do
    data = Admin.get_server_data(socket.assigns.match)
    user_stats = Admin.get_user_stats()

    rates = data.rates
    normal_rates = rates_by_list(rates, Game.list_normal_skills())
    ult_rates = rates_by_list(rates, Game.list_ultimate_skills())

    arena = data.arena
    bots = Enum.filter(arena, fn hero -> hero.bot_difficulty end)

    assign(socket,
      players: data.players,
      arena: Enum.sort_by(arena, & &1.pvp_ranking, :asc),
      bots: bots,
      normal_rates: normal_rates,
      ult_rates: ult_rates,
      user_stats: user_stats)
  end

  defp rates_by_list(rates, list) do
    codes = list |> Enum.map(fn skill -> skill.code end)

    rates
    |> Enum.sort_by(fn {_, {rate, _count}} -> rate end, :desc)
    |> Enum.filter(fn {skill, _} -> Enum.member?(codes, skill.code) end)
  end
end
