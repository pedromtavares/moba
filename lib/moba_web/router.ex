defmodule MobaWeb.Router do
  use MobaWeb, :router
  use Pow.Phoenix.Router
  use Pow.Extension.Phoenix.Router, otp_app: :moba
  import Phoenix.LiveDashboard.Router

  if Mix.env() == :dev do
    forward "/sent_emails", Bamboo.SentEmailViewerPlug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    # plug :put_root_layout, {MobaWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :base_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :pow_layout do
    plug :put_pow_layout, %{"html" => {MobaWeb.LayoutView, :root}}
  end

  pipeline :admin_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :admin}
  end

  pipeline :protected do
    plug Pow.Plug.RequireAuthenticated,
      error_handler: Pow.Phoenix.PlugErrorHandler
  end

  pipeline :player_protected do
    plug MobaWeb.PlayerAuth
  end

  pipeline :admin_protected do
    plug MobaWeb.AdminAuth
  end

  scope "/" do
    pipe_through [:browser, :pow_layout]

    pow_routes()
    pow_extension_routes()

    get "/start", MobaWeb.GameController, :start
    post "/start", MobaWeb.GameController, :create

    get "/", MobaWeb.GameController, :index
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

  scope "/admin", MobaWeb do
    pipe_through [:browser, :protected, :admin_protected]

    resources "/skills", Admin.SkillController
    resources "/items", Admin.ItemController
    resources "/avatars", Admin.AvatarController
    resources "/users", Admin.UserController
    resources "/skins", Admin.SkinController

    live_dashboard "/dashboard", metrics: MobaWeb.Telemetry, ecto_repos: [Moba.Repo]

    get "/", Admin.SkillController, :root
  end

  scope "/admin/seasons", MobaWeb do
    pipe_through [:browser, :protected, :admin_protected, :admin_layout]
    live "/current", Admin.SeasonLiveView
  end

  defp put_pow_layout(conn, layout), do: put_private(conn, :phoenix_layout, layout)
end
