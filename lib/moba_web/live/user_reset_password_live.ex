defmodule MobaWeb.UserResetPasswordLive do
  use MobaWeb, :live_view
  import MobaWeb.V2.Components.AccountComponents, only: [account_panel: 1]

  alias Moba.Accounts

  def render(assigns) do
    ~H"""
    <%= if assigns[:preview] do %>
      <%= if @invalid_link do %>
        <.account_panel
          id="account-reset-expired"
          title="Reset link unavailable"
          subtitle="This link is invalid or has expired. Request a fresh link to continue."
        >
          <.link id="request-new-reset" href={preview_path(assigns, ~p"/users/reset_password")} class="account-primary">
            Request a new reset link
          </.link>
          <:footer><.link href={preview_path(assigns, ~p"/users/log_in")}>← Back to sign in</.link></:footer>
        </.account_panel>
      <% else %>
        <.account_panel
          id="account-reset"
          title="Choose a new password"
          subtitle="Set a new password to get back into the game."
        >
          <.form for={@form} id="reset_password_form" phx-submit="reset_password" phx-change="validate">
            <p :if={@check_errors} class="account-form-error" role="alert">Check the highlighted fields below.</p>
            <.input
              field={@form[:password]}
              type="password"
              label="New password"
              class="account-input"
              autocomplete="new-password"
              required
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              class="account-input"
              autocomplete="new-password"
              required
            />
            <button type="submit" id="reset-account-password" class="account-primary" phx-disable-with="Resetting…">
              Reset password
            </button>
          </.form>
          <:footer><.link href={preview_path(assigns, ~p"/users/log_in")}>← Back to sign in</.link></:footer>
        </.account_panel>
      <% end %>
    <% else %>
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
                    <%= if @check_errors do %>
                      <p class="alert alert-danger">Oops, something went wrong! Please check the errors below.</p>
                    <% end %>

                    <div class="form-group">
                      <div class="d-flex flex-wrap align-items-baseline mb-1">
                        <label class="mb-0 mr-2">New Password</label>
                        <%= for error <- @form[:password].errors do %>
                          <span class="text-danger small mr-2">{translate_error(error)}</span>
                        <% end %>
                      </div>
                      <input
                        type="password"
                        id={@form[:password].id}
                        name={@form[:password].name}
                        value={@form[:password].value}
                        class="form-control"
                        required
                      />
                    </div>
                    <div class="form-group">
                      <div class="d-flex flex-wrap align-items-baseline mb-1">
                        <label class="mb-0 mr-2">Confirm New Password</label>
                        <%= for error <- @form[:password_confirmation].errors do %>
                          <span class="text-danger small mr-2">{translate_error(error)}</span>
                        <% end %>
                      </div>
                      <input
                        type="password"
                        id={@form[:password_confirmation].id}
                        name={@form[:password_confirmation].name}
                        value={@form[:password_confirmation].value}
                        class="form-control"
                        required
                      />
                    </div>
                    <div class="form-group mb-0 text-center">
                      <button class="btn btn-primary btn-block" type="submit" phx-disable-with="Resetting...">
                        Reset Password
                      </button>
                    </div>
                  </.form>

                  <p class="text-center mt-4 mb-0">
                    <.link href={preview_path(assigns, ~p"/users/register")} class="text-muted ml-1">Register</.link>
                    | <.link href={preview_path(assigns, ~p"/users/log_in")} class="text-muted ml-1">Log in</.link>
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
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

    {:ok, socket |> assign(check_errors: false) |> assign_form(form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: preview_path(socket, ~p"/users/log_in"))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(check_errors: true)
         |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)

    {:noreply,
     socket
     |> assign(check_errors: false)
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token, invalid_link: false)
    else
      if Map.get(socket.assigns, :preview, false) do
        assign(socket, invalid_link: true)
      else
        socket
        |> put_flash(:error, "Reset password link is invalid or it has expired.")
        |> redirect(to: preview_path(socket, ~p"/"))
      end
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
