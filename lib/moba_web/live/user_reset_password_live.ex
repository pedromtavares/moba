defmodule MobaWeb.UserResetPasswordLive do
  use MobaWeb, :live_view

  alias Moba.Accounts

  def render(assigns) do
    ~H"""
    <style>
      body::before {
        background-image: url(/images/home.jpg);
        background-size: cover;
        content: "";
        display: block;
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        z-index: -2;
        opacity: 0.2;
      }
    </style>
    <div class="account-pages mb-5" style="margin-top: 10rem">
      <div class="container">
        <div class="row justify-content-center">
          <div class="col-md-8 col-lg-6 col-xl-5">
            <div class="card black-bar">
              <div class="card-body pt-4 pl-4 pr-4">
                <div class="text-center w-75 m-auto">
                  <h3>Reset Password</h3>
                </div>

                <.form for={@form} id="reset_password_form" phx-submit="reset_password" phx-change="validate">
                  <%= if @form.errors != [] do %>
                    <p class="alert alert-danger">Oops, something went wrong! Please check the errors below.</p>
                  <% end %>

                  <div class="form-group">
                    <label>New Password</label>
                    <%= for error <- @form[:password].errors do %>
                      <span class="text-danger small d-block">{translate_error(error)}</span>
                    <% end %>
                    <input type="password" id={@form[:password].id} name={@form[:password].name} class="form-control" required />
                  </div>
                  <div class="form-group">
                    <label>Confirm New Password</label>
                    <%= for error <- @form[:password_confirmation].errors do %>
                      <span class="text-danger small d-block">{translate_error(error)}</span>
                    <% end %>
                    <input type="password" id={@form[:password_confirmation].id} name={@form[:password_confirmation].name} class="form-control" required />
                  </div>
                  <div class="form-group mb-0 text-center">
                    <button class="btn btn-primary btn-block" type="submit" phx-disable-with="Resetting...">Reset Password</button>
                  </div>
                </.form>

                <p class="text-center mt-4 mb-0">
                  <.link href={~p"/users/register"} class="text-muted ml-1">Register</.link>
                  |
                  <.link href={~p"/users/log_in"} class="text-muted ml-1">Log in</.link>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
