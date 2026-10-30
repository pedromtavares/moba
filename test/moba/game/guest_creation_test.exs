defmodule Moba.Game.GuestCreationTest do
  use Moba.DataCase

  alias Moba.Game.Schema.{Hero, Player}
  alias Ecto.Adapters.SQL.Sandbox

  test "retrying an old start session does not create another hero after the original was archived" do
    key = UUID.uuid4()
    player = Game.start_guest!(key, base_avatar(), base_skills())
    original = player.current_pve_hero
    Game.archive_hero!(original)

    retry = Game.start_guest!(key, base_avatar(), base_skills())
    assert retry.id == player.id
    assert is_nil(retry.current_pve_hero_id)
    assert Repo.aggregate(from(h in Hero, where: h.player_id == ^player.id), :count) == 1
  end

  test "a failure during hero creation rolls back the guest player too" do
    key = UUID.uuid4()

    assert_raise KeyError, fn -> Game.start_guest!(key, base_avatar(), [nil]) end
    refute Repo.get_by(Player, guest_session_key: key)

    player = Game.start_guest!(key, base_avatar(), base_skills())
    assert player.current_pve_hero_id
  end

  test "a repeated invocation from a stale player snapshot reuses the hero, while a fresh invocation still works" do
    player = Game.create_player!(%{})
    first = Game.create_current_pve_hero!(%{name: "First"}, player, base_avatar(), base_skills())
    retry = Game.create_current_pve_hero!(%{name: "Retry"}, player, base_avatar(), base_skills())
    assert retry.id == first.id

    fresh = Game.get_player!(player.id)
    next = Game.create_current_pve_hero!(%{name: "Next"}, fresh, base_avatar(), base_skills())
    refute next.id == first.id
    assert Repo.aggregate(from(h in Hero, where: h.player_id == ^player.id), :count) == 2
  end

  test "a stale restart cannot clear the new current hero or create another replacement" do
    player = Game.start_guest!(UUID.uuid4(), base_avatar(), base_skills())
    original = player.current_pve_hero
    Game.archive_hero!(original)
    replacement = Game.create_current_pve_hero!(%{name: "Replacement"}, player, base_avatar(), base_skills())

    Game.archive_hero!(original)
    assert Game.get_player!(player.id).current_pve_hero_id == replacement.id
    retry = Game.create_current_pve_hero!(%{name: "Retry"}, player, base_avatar(), base_skills())
    assert retry.id == replacement.id
    assert Repo.aggregate(from(h in Hero, where: h.player_id == ^player.id), :count) == 2
  end

  test "simultaneous creation on independent database connections returns one player and hero" do
    key = UUID.uuid4()
    avatar = base_avatar()
    skills = base_skills()

    # These calls commit outside the sandbox so PostgreSQL really arbitrates
    # concurrent inserts. Cleanup is restricted to this test's unique key.
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        players = from p in Player, where: p.guest_session_key == ^key
        Repo.update_all(players, set: [current_pve_hero_id: nil])
        Repo.delete_all(players)
      end)
    end)

    [first_result, second_result] =
      concurrently(fn ->
        player = Game.start_guest!(key, avatar, skills)
        {player.id, player.current_pve_hero_id}
      end)

    assert first_result == second_result
    {player_id, hero_id} = first_result
    assert hero_id
    assert Repo.aggregate(from(p in Player, where: p.guest_session_key == ^key), :count) == 1
    assert Repo.aggregate(from(h in Hero, where: h.player_id == ^player_id), :count) == 1
    player = Game.get_player!(player_id)

    [first_invocation, second_invocation] =
      concurrently(fn ->
        Game.create_current_pve_hero!(%{name: "Next"}, player, avatar, skills).id
      end)

    assert first_invocation == second_invocation
    refute first_invocation == hero_id
    assert Repo.aggregate(from(h in Hero, where: h.player_id == ^player_id), :count) == 2
  end

  defp concurrently(callback) do
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:ready, self(), backend})

            receive do
              :go -> callback.()
            after
              5000 -> raise "Concurrent creation was never released"
            end
          end)
        end)
      end

    assert_receive {:ready, first, first_backend}, 5000
    assert_receive {:ready, second, second_backend}, 5000
    refute first_backend == second_backend
    send(first, :go)
    send(second, :go)
    Enum.map(tasks, &Task.await(&1, 5000))
  end
end
