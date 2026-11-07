defmodule MobaWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Database tests can run asynchronously in isolated SQL Sandbox transactions.
  Use synchronous tests when changing shared cache keys, application settings,
  or other global state; database access alone does not require serialization.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      use Phoenix.ChannelTest

      # The default endpoint for testing
      @endpoint MobaWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Moba.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Moba.Repo, {:shared, self()})
    end

    :ok
  end
end
