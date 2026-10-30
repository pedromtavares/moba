defmodule MobaWeb.UserConfirmationInstructionsLive do
  use MobaWeb, :live_view
  import MobaWeb.V2.Components.AccountComponents, only: [account_panel: 1]

  alias Moba.Accounts

  def render(assigns) do
    ~H"""
    <%= if assigns[:preview] do %>
      <.account_panel
        id="account-resend-confirmation"
        title={if Phoenix.Flash.get(@flash, :info), do: "Check your inbox", else: "Need a confirmation link?"}
        subtitle="We'll send a new link to verify your email address."
      >
        <.form for={@form} id="resend_confirmation_form" phx-submit="send_instructions">
          <.input
            field={@form[:email]}
            type="email"
            label="Email address"
            class="account-input"
            autocomplete="email"
            required
          />
          <button type="submit" id="resend-confirmation" class="account-primary" phx-disable-with="Sending…">
            Send confirmation link
          </button>
        </.form>
        <:footer>
          <.link href={preview_path(assigns, ~p"/users/log_in")}>← Back to sign in</.link><.link href={
            preview_path(assigns, ~p"/users/register")
          }>Create an account</.link>
        </:footer>
      </.account_panel>
    <% else %>
      <div class={["mx-auto max-w-sm", assigns[:preview] && "account-pages game-account"]}>
        <.header class="text-center">
          No confirmation instructions received?
          <:subtitle>We'll send a new confirmation link to your inbox</:subtitle>
        </.header>

        <.simple_form for={@form} id="resend_confirmation_form" phx-submit="send_instructions">
          <.input field={@form[:email]} type="email" placeholder="Email" required />
          <:actions>
            <.button phx-disable-with="Sending..." class="w-full">
              Resend confirmation instructions
            </.button>
          </:actions>
        </.simple_form>

        <p class="text-center mt-4">
          <.link href={preview_path(assigns, ~p"/users/register")}>Register</.link>
          | <.link href={preview_path(assigns, ~p"/users/log_in")}>Log in</.link>
        </p>
      </div>
    <% end %>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &Phoenix.VerifiedRoutes.unverified_url(MobaWeb.Endpoint, preview_path(socket, ~p"/users/confirm/#{&1}"))
      )
    end

    info =
      "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

    socket = put_flash(socket, :info, info)

    if Map.get(socket.assigns, :preview, false) do
      {:noreply, assign(socket, form: to_form(%{"email" => ""}, as: "user"))}
    else
      {:noreply, redirect(socket, to: preview_path(socket, ~p"/"))}
    end
  end
end
