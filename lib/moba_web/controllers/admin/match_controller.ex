defmodule MobaWeb.Admin.MatchController do
  use MobaWeb, :controller

  alias Moba.{Game, Admin}

  plug(:put_layout, {MobaWeb.LayoutView, "torch.html"})

  def index(conn, params) do
    case Admin.paginate_matches(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering matches. #{inspect(error)}")
        |> redirect(to: Routes.match_path(conn, :index))
    end
  end

  def show(conn, %{"id" => id}) do
    match = Admin.get_match!(id)

    {players, bots} = Admin.current_arena_heroes()

    rates = get_cached_rates(match.inserted_at)
    normal_rates = rates_by_list(rates, Game.list_normal_skills())
    ult_rates = rates_by_list(rates, Game.list_ultimate_skills())

    render(conn, "show.html",
      match: match,
      players: players,
      bots: bots,
      normal_rates: normal_rates,
      ult_rates: ult_rates
    )
  end

  def edit(conn, %{"id" => id}) do
    match = Admin.get_match!(id)
    changeset = Admin.change_match(match)
    render(conn, "edit.html", match: match, changeset: changeset)
  end

  def update(conn, %{"id" => id, "match" => match_params}) do
    match = Admin.get_match!(id)

    case Admin.update_match(match, match_params) do
      {:ok, match} ->
        conn
        |> put_flash(:info, "match updated successfully.")
        |> redirect(to: Routes.match_path(conn, :show, match))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", match: match, changeset: changeset)
    end
  end

  defp get_cached_rates(inserted_at) do
    case Cachex.get(:game_cache, "match-#{inserted_at}1") do
      {:ok, nil} -> put_cache(inserted_at)
      {:ok, rates} -> rates
    end
  end

  defp put_cache(inserted_at) do
    rates = Admin.recent_winrates(inserted_at)
    Cachex.put(:rates_cache, "match-#{inserted_at}", rates)
    rates
  end

  defp rates_by_list(rates, list) do
    codes = list |> Enum.map(fn skill -> skill.code end)

    rates
    |> Enum.sort_by(fn {_, {rate, _count}} -> rate end, :desc)
    |> Enum.filter(fn {skill, _} -> Enum.member?(codes, skill.code) end)
  end
end
