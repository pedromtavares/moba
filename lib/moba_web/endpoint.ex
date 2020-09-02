defmodule MobaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :moba
  use Appsignal.Phoenix

  @session_options [
    store: :cookie,
    key: "_moba_key",
    signing_salt: "5hkIoMFs",
    # 37 days
    max_age: 24 * 60 * 60 * 37
  ]

  socket "/socket", MobaWeb.UserSocket,
    websocket: true,
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket, websocket: [check_origin: false, connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :moba,
    gzip: false,
    # cache_control_for_etags: "public, max-age=86400",
    only: ~w(css fonts images resources js favicon.ico robots.txt)

  plug Plug.Static,
    at: "/uploads",
    from: Path.expand("./uploads"),
    gzip: false

  plug(
    Plug.Static,
    at: "/torch",
    from: {:torch, "priv/static"},
    gzip: true,
    cache_control_for_etags: "public, max-age=86400"
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session, @session_options

  plug Pow.Plug.Session,
    otp_app: :moba,
    session_ttl_renewal: :timer.hours(720),
    credentials_cache_store: {Pow.Store.CredentialsCache, ttl: :timer.hours(720), namespace: "credentials"}

  plug PowPersistentSession.Plug.Cookie

  plug MobaWeb.ReloadUserPlug

  plug MobaWeb.Router
end
