defmodule MobaWeb.ReturnController do
  use MobaWeb, :controller

  alias Moba.Accounts.ReturnCampaign
  alias MobaWeb.UserAuth

  plug :private_response

  def show(conn, _params), do: render_page(conn, false)

  def check(conn, %{"token" => token}) do
    case ReturnCampaign.preview(token) do
      {:ok, user} -> json(conn, %{username: user.username})
      :error -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_invitation"})
    end
  end

  def check(conn, _params), do: conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_invitation"})

  def enter(conn, %{"token" => token}) do
    case ReturnCampaign.redeem(token) do
      {:ok, %{user: user, player_id: player_id}} ->
        conn
        |> put_session(:player_id, player_id)
        |> put_session(:user_return_to, ~p"/base")
        |> put_flash(:info, "Welcome back, #{user.username}!")
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      :error ->
        conn |> put_status(:unprocessable_entity) |> render_page(true)
    end
  end

  def enter(conn, _params), do: conn |> put_status(:unprocessable_entity) |> render_page(true)

  defp render_page(conn, invalid?) do
    conn
    |> assign(:invalid_invitation, invalid?)
    |> assign(:form, Phoenix.Component.to_form(%{}, as: :invitation))
    |> assign(:page_title, "Welcome back")
    |> render(:show, layout: false)
  end

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("x-frame-options", "DENY")
  end
end
