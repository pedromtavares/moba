defmodule MobaWeb.UserRegistrationLive do
  use MobaWeb, :live_view

  alias Moba.Accounts
  alias Moba.Accounts.Schema.User
  alias Moba

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
    <div class="account-pages mt-3">
      <div class="container-fluid">
        <div class="row justify-content-center">
          <div class="col-md-8 col-lg-6 col-xl-4">
            <div class="card black-bar">
              <div class="card-body p-4">
                <div class="text-center w-75 m-auto">
                  <h3 class="text-primary">Create an account</h3>
                  <p class="text-white">You must have an account before playing in the PvP Arena</p>
                </div>

                <.form
                  for={@form}
                  id="registration_form"
                  phx-submit="save"
                  phx-change="validate"
                  phx-trigger-action={@trigger_submit}
                  action={~p"/users/log_in?_action=registered"}
                  method="post"
                >
                  <%= if @check_errors do %>
                    <p class="alert alert-danger">Oops, something went wrong! Please check the errors below.</p>
                  <% end %>

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
                      <label class="mb-0 mr-2">Password</label>
                      <%= for error <- @form[:password].errors do %>
                        <span class="text-danger small mr-2">{translate_error(error)}</span>
                      <% end %>
                    </div>
                    <input type="password" id={@form[:password].id} name={@form[:password].name} value={@form[:password].value} class="form-control" required />
                  </div>
                  <div class="form-group mb-3">
                    <div class="d-flex flex-wrap align-items-baseline mb-1">
                      <label class="mb-0 mr-2">E-mail <small>(used only for account recovery)</small></label>
                      <%= for error <- @form[:email].errors do %>
                        <span class="text-danger small mr-2">{translate_error(error)}</span>
                      <% end %>
                    </div>
                    <input type="email" id={@form[:email].id} name={@form[:email].name} value={@form[:email].value} class="form-control" required />
                  </div>
                  <div class="form-group mb-0 text-center">
                    <button class="btn btn-primary btn-block" type="submit" phx-disable-with="Creating account...">Sign Up</button>
                  </div>
                </.form>
              </div>

              <div class="row mt-1">
                <div class="col-12 text-center">
                  <p class="text-muted">
                    Already have account?
                    <.link navigate={~p"/users/log_in"} class="text-muted font-weight-medium ml-1">Sign In</.link>
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false, player_id: session["player_id"])
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Moba.after_registration(user, socket.assigns.player_id)

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
