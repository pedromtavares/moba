defmodule MobaWeb.UserSessionController do
  use MobaWeb, :controller

  alias Moba.Accounts
  alias MobaWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, preview_path(conn, ~p"/users/settings"))
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params} = params, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> maybe_guide_training(params, user)
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: preview_path(conn, ~p"/users/log_in"))
    end
  end

  defp maybe_guide_training(conn, %{"_action" => "registered", "from" => "training"}, user) do
    player_id = get_session(conn, :player_id)

    case player_id && Moba.Repo.get(Moba.Game.Schema.Player, player_id) do
      %{user_id: user_id} when user_id == user.id ->
        conn
        |> put_session(:user_return_to, ~p"/base")
        |> put_flash(:training_registered, "Start training")

      _ ->
        conn
    end
  end

  defp maybe_guide_training(conn, _params, _user), do: conn

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
