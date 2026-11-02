defmodule MobaWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MobaWeb.ConnCase
      alias MobaWeb.Router.Helpers, as: Routes

      import Test.AccountsHelper
      import Test.GameHelper
      import Test.EngineHelper

      alias Moba.Game
      alias Moba.Accounts
      alias Moba.Engine
      alias Moba.Admin
      alias Moba.Conductor

      # The default endpoint for testing
      @endpoint MobaWeb.Endpoint

      use MobaWeb, :verified_routes
    end
  end

  setup tags do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Moba.Repo, shared: !tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Moba.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    token = Moba.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc "Builds an authenticated player session, or a guest session for a guest player."
  def log_in_player(conn, session) do
    player = Moba.Game.get_player!(Keyword.fetch!(session, :player_id))
    conn = if player.user, do: log_in_user(conn, player.user), else: Phoenix.ConnTest.init_test_session(conn, %{})
    Enum.reduce(session, conn, fn {key, value}, conn -> Plug.Conn.put_session(conn, key, value) end)
  end
end
