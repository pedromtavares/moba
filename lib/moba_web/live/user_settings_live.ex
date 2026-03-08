defmodule MobaWeb.UserSettingsLive do
  use MobaWeb, :live_view

  alias Moba.Accounts

  def render(assigns) do
    ~H"""
    <div class="account-pages mt-2">
      <div class="container">
        <div class="row">
          <div class="col-12 text-center">
            <p class="text-muted">
              <.link navigate={~p"/user/#{@current_user.id}"} class="text-muted font-weight-medium ml-1">
                Back to Profile
              </.link>
            </p>
          </div>
        </div>
        <div class="row justify-content-center">
          <div class="col-md-8 col-lg-6 col-xl-5">
            <div class="card">
              <div class="card-body p-4">
                <div class="text-center w-75 m-auto">
                  <h3>Edit Profile</h3>
                </div>

                <%= if error = Phoenix.Flash.get(@flash, :error) do %>
                  <p class="alert alert-danger" role="alert">{error}</p>
                <% end %>
                <%= if info = Phoenix.Flash.get(@flash, :info) do %>
                  <p class="alert alert-info" role="alert">{info}</p>
                <% end %>

                <.form for={@form} id="settings_form" phx-submit="save">
                  <div class="form-group">
                    <div class="d-flex flex-wrap align-items-baseline mb-1">
                      <label class="mb-0 mr-2">Username</label>
                      <%= for error <- @form[:username].errors do %>
                        <span class="text-danger small mr-2">{translate_error(error)}</span>
                      <% end %>
                    </div>
                    <input type="text" id={@form[:username].id} name={@form[:username].name} value={@form[:username].value} class="form-control" required />
                  </div>
                  <div class="form-group">
                    <div class="d-flex flex-wrap align-items-baseline mb-1">
                      <label class="mb-0 mr-2">E-mail</label>
                      <%= for error <- @form[:email].errors do %>
                        <span class="text-danger small mr-2">{translate_error(error)}</span>
                      <% end %>
                    </div>
                    <input type="email" id={@form[:email].id} name={@form[:email].name} value={@form[:email].value} class="form-control" required />
                  </div>
                  <div class="form-group">
                    <div class="d-flex flex-wrap align-items-baseline mb-1">
                      <label class="mb-0 mr-2">Password</label>
                      <%= for error <- @form[:password].errors do %>
                        <span class="text-danger small mr-2">{translate_error(error)}</span>
                      <% end %>
                    </div>
                    <input type="password" id={@form[:password].id} name={@form[:password].name} value={@form[:password].value} class="form-control" />
                  </div>
                  <div class="form-group">
                    <div class="d-flex flex-wrap align-items-baseline mb-1">
                      <label class="mb-0 mr-2">Confirm Password</label>
                      <%= for error <- @form[:password_confirmation].errors do %>
                        <span class="text-danger small mr-2">{translate_error(error)}</span>
                      <% end %>
                    </div>
                    <input type="password" id={@form[:password_confirmation].id} name={@form[:password_confirmation].name} value={@form[:password_confirmation].value} class="form-control" />
                  </div>
                  <div class="form-group mb-0 text-center">
                    <button class="btn btn-primary btn-block" type="submit" phx-disable-with="Updating...">Update</button>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok -> put_flash(socket, :info, "Email changed successfully.")
        :error -> put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_settings(socket.assigns.current_user)
    {:ok, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.update_user_settings(socket.assigns.current_user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user, form: to_form(Accounts.change_user_settings(user)))
         |> put_flash(:info, "Profile updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
