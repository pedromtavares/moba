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

    data = Admin.Server.get_data(match)

    rates = data.rates
    normal_rates = rates_by_list(rates, Game.list_normal_skills())
    ult_rates = rates_by_list(rates, Game.list_ultimate_skills())

    render(conn, "show.html",
      match: match,
      players: Enum.sort_by(data.players, & &1.pvp_ranking, :asc),
      bots: data.bots,
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

  defp rates_by_list(rates, list) do
    codes = list |> Enum.map(fn skill -> skill.code end)

    rates
    |> Enum.sort_by(fn {_, {rate, _count}} -> rate end, :desc)
    |> Enum.filter(fn {skill, _} -> Enum.member?(codes, skill.code) end)
  end
end
