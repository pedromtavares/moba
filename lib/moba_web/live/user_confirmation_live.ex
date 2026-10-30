defmodule MobaWeb.UserConfirmationLive do
  use MobaWeb, :live_view
  import MobaWeb.V2.Components.AccountComponents, only: [account_panel: 1]

  alias Moba.Accounts

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <%= if assigns[:preview] do %>
      <%= if @confirmation_error do %>
        <.account_panel
          id="account-confirmation-expired"
          title="Confirmation link unavailable"
          subtitle="This link is invalid or has expired. Request a new link to verify your email."
        >
          <.link id="request-new-confirmation" href={preview_path(assigns, ~p"/users/confirm")} class="account-primary">
            Request a new confirmation link
          </.link>
          <:footer><.link href={preview_path(assigns, ~p"/users/log_in")}>← Back to sign in</.link></:footer>
        </.account_panel>
      <% else %>
        <.account_panel
          id="account-confirmation"
          title="Confirm your account"
          subtitle="Verify your email address to complete your account setup."
        >
          <.form for={@form} id="confirmation_form" phx-submit="confirm_account">
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <button type="submit" id="confirm-account" class="account-primary" phx-disable-with="Confirming…">
              Confirm account
            </button>
          </.form>
          <:footer>
            <.link href={preview_path(assigns, ~p"/users/confirm")}>Request a new link</.link><.link href={
              preview_path(assigns, ~p"/users/log_in")
            }>Sign in</.link>
          </:footer>
        </.account_panel>
      <% end %>
    <% else %>
      <div class={["mx-auto max-w-sm", assigns[:preview] && "account-pages game-account"]}>
        <.header class="text-center">Confirm Account</.header>

        <.simple_form for={@form} id="confirmation_form" phx-submit="confirm_account">
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <:actions>
            <.button phx-disable-with="Confirming..." class="w-full">Confirm my account</.button>
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

  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")
    {:ok, assign(socket, form: form, confirmation_error: false), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User confirmed successfully.")
         |> redirect(to: preview_path(socket, ~p"/"))}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: preview_path(socket, ~p"/"))}

          %{} ->
            if Map.get(socket.assigns, :preview, false) do
              {:noreply, assign(socket, confirmation_error: true)}
            else
              {:noreply,
               socket
               |> put_flash(:error, "User confirmation link is invalid or it has expired.")
               |> redirect(to: preview_path(socket, ~p"/"))}
            end
        end
    end
  end
end
