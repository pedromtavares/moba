defmodule Moba.ServerTest do
  use ExUnit.Case, async: true

  test "maintenance and cache messages do not access the database during tests" do
    server = start_supervised!({Moba.Server, name: __MODULE__})
    monitor = Process.monitor(server)

    # This process has no Sandbox checkout or allowance. A database query would
    # crash it; querying the state also ensures each message has been handled.
    for message <- [:server_check, :warm_caches] do
      send(server, message)
      assert :sys.get_state(server) == []
    end

    refute_receive {:DOWN, ^monitor, :process, ^server, _reason}, 0
  end
end
