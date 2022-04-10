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
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :root_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :pow_layout do
    plug :put_pow_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :protected do
    plug Pow.Plug.RequireAuthenticated,
      error_handler: Pow.Phoenix.PlugErrorHandler
  end

  pipeline :admin_protected do
    plug MobaWeb.AdminAuth
  end

  pipeline :user_helper do
    plug MobaWeb.AuthHelper
  end

  scope "/" do
    pipe_through [:browser, :user_helper, :pow_layout]

    pow_routes()
    pow_extension_routes()

    get "/start", MobaWeb.GameController, :start
    post "/start", MobaWeb.GameController, :create

    get "/", MobaWeb.GameController, :index
  end

  scope "/" do
    pipe_through [:browser, :user_helper, :root_layout]

    live "/battles/:id", MobaWeb.BattleLiveView
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :root_layout, :protected, :user_helper]

    live_session :default, on_mount: MobaWeb.UserLiveAuth do
      live "/invoke", CreateLiveView

      live "/training", TrainingLiveView

      live "/battles", BattlesLiveView

      live "/base", DashboardLiveView

      live "/arena", ArenaLiveView
      live "/arena/:id", DuelLiveView

      live "/user/:id", UserLiveView

      live "/hero/:id", HeroLiveView

      live "/tavern", TavernLiveView

      live "/community", CommunityLiveView

      live "/library", LibraryLiveView
    end
  end

  scope "/admin", MobaWeb do
    pipe_through [:browser, :protected, :admin_protected]

    resources "/skills", Admin.SkillController
    resources "/items", Admin.ItemController
    resources "/avatars", Admin.AvatarController
    resources "/users", Admin.UserController
    resources "/matches", Admin.MatchController
    resources "/skins", Admin.SkinController
    resources "/quests", Admin.QuestController

    live_dashboard "/dashboard", metrics: MobaWeb.Telemetry, ecto_repos: [Moba.Repo]

    get "/", Admin.SkillController, :root
  end

  defp put_pow_layout(conn, layout), do: put_private(conn, :phoenix_layout, layout)
end
