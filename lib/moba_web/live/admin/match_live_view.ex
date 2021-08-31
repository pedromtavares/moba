defmodule MobaWeb.Admin.MatchLiveView do
  use MobaWeb, :live_view

  alias Moba.{Game, Admin}

  def mount(_, session, socket) do
    if connected?(socket), do: MobaWeb.subscribe("admin")

    match_id = Map.get(session, "match_id")

    match =
      case match_id do
        nil -> Game.current_match()
        "current" -> Game.current_match()
        _ -> Admin.get_match!(match_id)
      end

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

    arena_master = data.arena_master
    arena_grandmaster = data.arena_grandmaster

    assign(socket,
      players: data.players,
      arena_master: sort_arena(arena_master),
      arena_grandmaster: sort_arena(arena_grandmaster),
      bots_master: filter_bots(arena_master),
      bots_grandmaster: filter_bots(arena_grandmaster),
      normal_rates: normal_rates,
      ult_rates: ult_rates,
      user_stats: user_stats,
      last_updated: Timex.now()
    )
  end

  defp rates_by_list(rates, list) do
    codes = list |> Enum.map(fn skill -> skill.code end)

    rates
    |> Enum.sort_by(fn {_, {rate, _count}} -> rate end, :desc)
    |> Enum.filter(fn {skill, _} -> Enum.member?(codes, skill.code) end)
  end

  defp sort_arena(heroes), do: Enum.sort_by(heroes, & &1.pvp_ranking, :asc)
  defp filter_bots(heroes), do: Enum.filter(heroes, fn hero -> hero.bot_difficulty end)
end
