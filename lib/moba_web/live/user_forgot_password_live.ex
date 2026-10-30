defmodule MobaWeb.UserForgotPasswordLive do
  use MobaWeb, :live_view
  import MobaWeb.V2.Components.AccountComponents, only: [account_panel: 1]

  alias Moba.Accounts

  def render(assigns) do
    ~H"""
    <%= if assigns[:preview] do %>
      <.account_panel
        id="account-recovery"
        title={if Phoenix.Flash.get(@flash, :info), do: "Check your inbox", else: "Recover your account"}
        subtitle="Request a link to reset your password."
      >
        <p :if={Phoenix.Flash.get(@flash, :info)} class="account-inline-success" id="recovery-sent">
          If the email matches an account, your reset instructions are on their way.
        </p>
        <.form
          for={@form}
          id="reset_password_form"
          phx-submit="send_email"
          phx-hook="ResetFormOnEvent"
          data-reset-event="reset-password-form"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email address"
            class="account-input"
            autocomplete="email"
            required
          />
          <button type="submit" id="send-reset-link" class="account-primary" phx-disable-with="Sending…">
            {if Phoenix.Flash.get(@flash, :info), do: "Send another link", else: "Send reset link"}
          </button>
        </.form>
        <:footer>
          <.link href={preview_path(assigns, ~p"/users/log_in")}>← Back to sign in</.link><.link href={
            preview_path(assigns, ~p"/users/register")
          }>Create an account</.link>
        </:footer>
      </.account_panel>
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
                    <h3>Forgot your password?</h3>
                    <p class="text-white">We'll send a password reset link to your inbox</p>
                  </div>

                  <%= if info = Phoenix.Flash.get(@flash, :info) do %>
                    <p class="alert alert-success" role="alert">{info}</p>
                  <% end %>

                  <.form
                    for={@form}
                    id="reset_password_form"
                    phx-submit="send_email"
                    phx-hook="ResetFormOnEvent"
                    data-reset-event="reset-password-form"
                  >
                    <div class="form-group">
                      <label>E-mail</label>
                      <input
                        type="email"
                        id={@form[:email].id}
                        name={@form[:email].name}
                        value={@form[:email].value}
                        class="form-control"
                        required
                      />
                    </div>
                    <div class="form-group mb-0 text-center">
                      <button class="btn btn-primary btn-block" type="submit" phx-disable-with="Sending...">
                        Send password reset instructions
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

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: empty_form())}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &Phoenix.VerifiedRoutes.unverified_url(MobaWeb.Endpoint, preview_path(socket, ~p"/users/reset_password/#{&1}"))
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> assign(form: empty_form())
     |> push_event("reset-password-form", %{})}
  end

  defp empty_form do
    to_form(%{"email" => ""}, as: "user")
  end
end
