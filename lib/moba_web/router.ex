defmodule MobaWeb.Router do
  use MobaWeb, :router

  import MobaWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  if Mix.env() == :dev do
    forward "/dev/mailbox", Plug.Swoosh.MailboxPreview
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    # plug :put_root_layout, {MobaWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :base_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :admin_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :admin}
  end

  pipeline :protected do
    plug :require_authenticated_user
  end

  pipeline :player_protected do
    plug MobaWeb.PlayerAuth
  end

  pipeline :admin_protected do
    plug MobaWeb.AdminAuth
  end

  scope "/" do
    pipe_through [:browser]

    get "/", MobaWeb.GameController, :index
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :require_authenticated_user, :base_layout]

    get "/start", GameController, :start
    post "/start", GameController, :create
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :base_layout]

    live "/battles/:id", BattleLive
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :player_protected, :base_layout]

    get "/auth", AuthController, :start
    get "/auth/:provider", AuthController, :request
    get "/auth/:provider/callback", AuthController, :callback

    live_session :default, on_mount: MobaWeb.PlayerLiveAuth do
      live "/invoke", CreateLive

      live "/training", TrainingLive

      live "/battles", BattlesLive

      live "/base", DashboardLive

      live "/arena", ArenaLive.Index
      live "/arena/edit", ArenaLive.Edit, :edit, as: :edit_arena
      live "/arena/:id", DuelLive

      live "/matches/:id", MatchLive

      live "/user/:id", PlayerLive
      live "/player/:player_id", PlayerLive, :show, as: :player

      live "/hero/:id", HeroLive

      live "/tavern", TavernLive

      live "/community", CommunityLive

      live "/library", LibraryLive
    end
  end

  # V2 routes — separate live_session, separate layout, separate asset pipeline
  scope "/v2", MobaWeb.V2 do
    pipe_through [:browser, :player_protected]

    live_session :v2_game,
      on_mount: [
        MobaWeb.V2.Hooks.RequireAuth,
        MobaWeb.V2.Hooks.LoadGameState
      ],
      root_layout: {MobaWeb.V2.Layouts, :root} do
      live "/base", DashboardLive
    end
  end

  scope "/admin", MobaWeb do
    pipe_through [:browser, :protected, :admin_protected]

    resources "/skills", Admin.SkillController
    resources "/items", Admin.ItemController
    resources "/avatars", Admin.AvatarController
    resources "/users", Admin.UserController
    resources "/skins", Admin.SkinController

    live_dashboard "/dashboard", metrics: MobaWeb.Telemetry, ecto_repos: [Moba.Repo]

    get "/", Admin.UserController, :index
  end

  ## Authentication routes

  scope "/", MobaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      root_layout: {MobaWeb.LayoutView, :root},
      on_mount: [{MobaWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      root_layout: {MobaWeb.LayoutView, :root},
      on_mount: [{MobaWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", MobaWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{MobaWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
