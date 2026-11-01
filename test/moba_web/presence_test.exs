defmodule MobaWeb.PresenceTest do
  use ExUnit.Case, async: true

  alias MobaWeb.Presence

  defp player do
    %{id: -System.unique_integer([:positive]), pvp_tier: 0, pvp_points: 0}
  end

  test "updating an untracked process returns nopresence instead of raising" do
    assert {:error, :nopresence} = Presence.update_player(self(), player())
  end

  test "metadata updates preserve the specified tab's metadata and leave other tabs unchanged" do
    player = player()
    first = start_supervised!({Agent, fn -> :first end}, id: :first_tab)
    second = start_supervised!({Agent, fn -> :second end}, id: :second_tab)

    for {pid, tab} <- [{first, :first}, {second, :second}] do
      {:ok, _} = Presence.track(pid, "online", player.id, Map.put(player, :tab, tab))
    end

    # Deliberately update the tab that is not first in the grouped metadata.
    [head | _] = Presence.get_by_key("online", player.id).metas
    {pid, tab} = if head.tab == :first, do: {second, :second}, else: {first, :first}
    {:ok, _} = Presence.update_player(pid, %{player | pvp_tier: 1, pvp_points: 42})
    metas = Presence.get_by_key("online", player.id).metas

    assert length(metas) == 2
    assert Enum.sort(Enum.map(metas, & &1.tab)) == [:first, :second]
    assert %{pvp_tier: 1, pvp_points: 42} = Enum.find(metas, &(&1.tab == tab))
    assert %{pvp_tier: 0, pvp_points: 0} = Enum.find(metas, &(&1.tab != tab))
  end

  test "closing one tab leaves the other tab present" do
    player = player()
    key = to_string(player.id)
    MobaWeb.subscribe("online")
    first = start_supervised!({Agent, fn -> :first end}, id: :first_tab)
    second = start_supervised!({Agent, fn -> :second end}, id: :second_tab)
    {:ok, _} = Presence.track_player(first, player)
    {:ok, _} = Presence.track_player(second, player)
    assert length(Presence.get_by_key("online", player.id).metas) == 2

    monitor = Process.monitor(first)
    stop_supervised!(:first_tab)
    assert_receive {:DOWN, ^monitor, :process, ^first, _}
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{leaves: %{^key => _}}}, 1000
    assert [%{player_id: id}] = Presence.get_by_key("online", player.id).metas
    assert id == player.id
  end
end
