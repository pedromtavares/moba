defmodule MobaWeb.UserRegistrationLive do
  use MobaWeb, :live_view

  alias Moba.Accounts
  alias Moba.Game.{TeamRuns, TeamTraining}
  alias Moba.Game.Schema.Player
  alias Moba.Repo
  alias MobaWeb.V2.Components.GameHelpers, as: V2Helpers
  import MobaWeb.V2.Components.GameComponents, only: [league_badge: 1]
  alias Moba.Accounts.Schema.User
  alias Moba

  def render(%{training_preview: preview} = assigns) when not is_nil(preview) do
    ~H"""
    <main id="guest-registration" class="guest-registration" aria-labelledby="guest-registration-title">
      <picture class="guest-registration-scene" aria-hidden="true">
        <source media="(max-width: 700px)" srcset={~p"/images/landing/home-heroes-mobile-v1.webp"} />
        <img src={~p"/images/landing/home-heroes-v5.png"} alt="" fetchpriority="high" />
      </picture>
      <header class="guest-registration-header">
        <span class="guest-registration-brand">
          <img src={~p"/images/navigation/base.webp"} width="40" height="40" alt="" /> <span>Browser MOBA</span>
        </span>
        <.link
          id="guest-registration-sign-in"
          navigate={preview_path(assigns, ~p"/users/log_in")}
          class="guest-registration-sign-in"
        >
          <.icon name="game-sign-in" /> Already registered? <strong>Sign in</strong>
        </.link>
      </header>
      <div class="guest-registration-content">
        <div class="guest-registration-story">
          <h1 id="guest-registration-title">Register to <span>enter the Arena.</span></h1>
          <p>Take your team to the test in team fights against other players in PvP</p>
          <section
            :if={@training_preview.heroes != []}
            id="guest-registration-roster"
            aria-label={@training_preview.team? && "Training roster"}
            aria-labelledby={!@training_preview.team? && "guest-roster-title"}
          >
            <div class="guest-roster-heading">
              <h2 :if={!@training_preview.team?} id="guest-roster-title">Your hero</h2>
              <div class="guest-roster-league">
                <.league_badge tier={@training_preview.tier} variant="legacy" />
                <span aria-hidden="true">{V2Helpers.league_name(@training_preview.tier)}</span>
              </div>
            </div>
            <ul class={["guest-roster-portraits", !@training_preview.team? && "is-solo"]}>
              <li :for={hero <- @training_preview.heroes} class="guest-roster-hero">
                <img src={V2Helpers.background_url(hero)} alt="" />
                <span class="guest-roster-caption">
                  <strong>{hero.avatar.name}</strong>
                  <span>Level {hero.level}</span>
                </span>
              </li>
            </ul>
          </section>
        </div>
        <section class="guest-registration-panel" aria-labelledby="guest-registration-form-title">
          <header class="guest-registration-panel-header">
            <h2 id="guest-registration-form-title">Create an account</h2>
            <img src={~p"/images/navigation/arena.webp"} width="36" height="36" alt="" />
          </header>
          <.registration_form {assigns} cinematic />
        </section>
      </div>
    </main>
    """
  end

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

                <.registration_form {assigns} />
              </div>

              <div class="row mt-1">
                <div class="col-12 text-center">
                  <p class="text-muted">
                    Already have account?
                    <.link navigate={preview_path(assigns, ~p"/users/log_in")} class="text-muted font-weight-medium ml-1">
                      Sign In
                    </.link>
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

  defp registration_form(assigns) do
    assigns = assign_new(assigns, :cinematic, fn -> false end)

    ~H"""
    <.form
      for={@form}
      id="registration_form"
      phx-submit="save"
      phx-change="validate"
      phx-trigger-action={@trigger_submit}
      action={preview_path(assigns, @registration_action)}
      method="post"
    >
      <p :if={@check_errors} class="alert alert-danger" role="alert">Please check the fields below.</p>

      <div
        :for={
          {key, label, type, autocomplete} <- [
            {:username, "Username", "text", "username"},
            {:password, "Password", "password", "new-password"},
            {:email, "Email (for account recovery)", "email", "email"}
          ]
        }
        class="form-group"
      >
        <% field = @form[key] %>
        <.input
          id={field.id}
          name={field.name}
          value={field.value}
          errors={Enum.map(field.errors, &translate_error/1)}
          label={label}
          type={type}
          autocomplete={autocomplete}
          aria-invalid={field.errors != [] && "true"}
          class="form-control"
          required
        />
      </div>
      <button :if={@cinematic} id="guest-registration-submit" class="guest-registration-submit" type="submit">
        Create account <span aria-hidden="true">→</span>
      </button>
      <button :if={!@cinematic} class="btn btn-primary btn-block" type="submit">Sign Up</button>
    </.form>
    """
  end

  def mount(params, session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    registration_action =
      if params["from"] == "training" && session["player_id"],
        do: ~p"/users/log_in?_action=registered&from=training",
        else: ~p"/users/log_in?_action=registered"

    socket =
      socket
      |> assign(
        trigger_submit: false,
        check_errors: false,
        player_id: session["player_id"],
        training_preview: training_preview(params, session["player_id"]),
        registration_action: registration_action
      )
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  defp training_preview(%{"from" => "training"}, player_id) when is_integer(player_id) do
    case Repo.get(Player, player_id) do
      %Player{user_id: nil} = player ->
        scope = %{user: nil, player_id: player.id}

        with %{phase: phase} = record when phase in ["playing", "engagement", "finished"] <-
               TeamRuns.latest(scope, player.id),
             {:ok, run} <- TeamRuns.read_state(record) do
          %{heroes: Enum.map(TeamTraining.team(run), & &1.hero), tier: run.league_tier, team?: true}
        else
          _ ->
            player = Repo.preload(player, current_pve_hero: [:avatar, :skin])
            hero = player.current_pve_hero
            %{heroes: List.wrap(hero), tier: hero && hero.league_tier, team?: false}
        end

      _ ->
        nil
    end
  end

  defp training_preview(_, _), do: nil

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
