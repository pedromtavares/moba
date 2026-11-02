defmodule Moba.BackendFourthIntegrityTest do
  use MobaWeb.ConnCase
  import Moba.DataCase, only: [errors_on: 1]
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias Moba.Repo
  alias Moba.Accounts.{Schema.User, UserToken}
  alias Moba.Game.Schema.{Avatar, Hero, Item, Match, Player, Skill, Team}

  test "duel pick checks continue after a battle and advance an expired later pick", %{conn: conn} do
    player = create_player!()
    duel = Game.create_duel!(player, create_player!(), false)
    duel |> Game.Schema.Duel.changeset(%{phase: "player_battle"}) |> Repo.update!()
    {:ok, view, _} = conn |> log_in_player(player_id: player.id) |> live("/arena/#{duel.id}")
    pid = view.pid
    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :check_phase}, 1500
    render(view)

    Game.get_duel!(duel.id)
    |> Game.Schema.Duel.changeset(%{
      phase: "opponent_second_pick",
      phase_changed_at: DateTime.add(DateTime.utc_now(), -120)
    })
    |> Repo.update!()

    send(pid, {"phase", %{}})
    render(view)
    assert_receive {:trace, ^pid, :receive, :check_phase}, 1500
    render(view)
    assert Game.get_duel!(duel.id).phase == "player_second_pick"
    :erlang.trace(pid, false, [:receive])
    GenServer.stop(pid)
  end

  test "manual starts reuse an unfinished match and award its shards only once" do
    player = create_player!()
    create_player!(%{total_matches: 1})
    balance = Accounts.get_user!(player.user_id).shard_count
    first = Game.manual_matchmaking!(player)
    for _ <- 1..35, do: assert(Game.manual_matchmaking!(player).id == first.id)
    assert Repo.aggregate(from(m in Match, where: m.player_id == ^player.id), :count) == 1
    assert Game.Arena.daily_reward_games(player) == 1
    assert Accounts.get_user!(player.user_id).shard_count == balance + Moba.matchmaking_shards()

    Game.Matches.update!(first, %{phase: "scored", winner_id: player.id})
    second = Game.manual_matchmaking!(player)
    assert second.id != first.id
    assert Accounts.get_user!(player.user_id).shard_count == balance + 2 * Moba.matchmaking_shards()
  end

  test "resuming a previous day's pending match grants no new reward" do
    player = create_player!()
    create_player!(%{total_matches: 1})
    match = Game.manual_matchmaking!(player)
    reset = Game.current_season().last_pvp_update_at
    Repo.update_all(from(m in Match, where: m.id == ^match.id), set: [inserted_at: DateTime.add(reset, -1)])
    balance = Accounts.get_user!(player.user_id).shard_count
    assert Game.manual_matchmaking!(player).id == match.id
    assert Accounts.get_user!(player.user_id).shard_count == balance
  end

  test "login and reset lookup ignore email capitalization without rewriting legacy addresses" do
    user = create_user()
    legacy = user |> Ecto.Changeset.change(email: String.upcase(user.email)) |> Repo.update!()
    {encoded, token} = UserToken.build_email_token(legacy, "reset_password")
    Repo.insert!(token)
    supplied = "  #{String.downcase(legacy.email)}  "
    assert Accounts.get_user_by_email(supplied).id == user.id
    assert Accounts.get_user_by_email_and_password(supplied, "123456").id == user.id
    assert Accounts.get_user_by_reset_password_token(encoded).id == user.id
    assert Accounts.get_user!(user.id).email == legacy.email
  end

  test "new emails are normalized and duplicate case variants are rejected" do
    email = "Identity#{System.unique_integer([:positive])}@EXAMPLE.invalid"
    attrs = %{username: "identitycheck", email: "  #{email}  ", password: "valid password123"}
    assert {:ok, user} = Accounts.register_user(attrs)
    assert user.email == String.downcase(email)

    assert {:error, changeset} =
             Accounts.register_user(%{attrs | username: "identityother", email: String.upcase(email)})

    assert "has already been taken" in errors_on(changeset).email
  end

  test "the database rejects normalized duplicates even when prevalidation is skipped" do
    user = create_user()
    attrs = %{username: "databaseunique", email: String.upcase(user.email), password: "valid password123"}
    changeset = User.registration_changeset(%User{}, attrs, validate_email: false)
    assert {:error, rejected} = Repo.insert(changeset, mode: :savepoint)
    assert "has already been taken" in errors_on(rejected).email
  end

  test "admin deletion removes owned teams and matches and handles surviving battle references", %{conn: conn} do
    player = create_player!()
    other = create_player!()
    team = Game.create_team!(%{player_id: player.id, name: "Saved"})
    create_base_hero(%{}, player)

    match =
      Game.Matches.create!(%{
        player_id: other.id,
        opponent_id: player.id,
        winner_id: player.id,
        player_picks: [],
        opponent_picks: [],
        generated_picks: [],
        type: "manual"
      })

    a = Game.create_hero!(%{name: "Borrowed A"}, other, base_avatar(), base_skills())
    b = Game.create_hero!(%{name: "Borrowed B"}, other, alternate_avatar(), base_skills())
    battle = create_basic_battle(a, b)

    battle
    |> Ecto.Changeset.change(
      attacker_player_id: player.id,
      defender_player_id: player.id,
      winner_player_id: player.id,
      initiator_player_id: player.id
    )
    |> Repo.update!()

    token = Accounts.generate_user_session_token(Accounts.get_user!(player.user_id))
    admin = create_user() |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
    response = conn |> log_in_user(admin) |> delete("/admin/users/#{player.user_id}")
    assert redirected_to(response) == "/admin/users"
    refute Repo.get(User, player.user_id)
    refute Repo.get(Player, player.id)
    refute Repo.get(Team, team.id)
    refute Repo.get(Match, match.id)
    refute Accounts.get_user_by_session_token(token)
    assert Repo.get(User, other.user_id)
    remaining = Engine.get_battle!(battle.id)

    for field <- [:attacker_player_id, :defender_player_id, :winner_player_id, :initiator_player_id],
        do: assert(is_nil(Map.fetch!(remaining, field)))
  end

  test "cleanup retains referenced resource versions and deletes unused versions" do
    hero = create_base_hero()
    skill = old_copy(base_skill())
    item = old_copy(base_item())
    avatar = old_copy(base_avatar(), %{ultimate_id: skill.id})
    hero |> Ecto.Changeset.change(avatar_id: avatar.id) |> Repo.update!()
    Game.get_hero!(hero.id) |> Game.update_hero!(%{}, [item], [skill])
    unused_avatar = old_copy(base_avatar())
    unused_skill = old_copy(base_skill())
    unused_item = old_copy(base_item())
    Moba.Cleaner.cleanup_old_records()
    assert Repo.get(Avatar, avatar.id)
    assert Repo.get(Skill, skill.id)
    assert Repo.get(Item, item.id)
    refute Repo.get(Avatar, unused_avatar.id)
    refute Repo.get(Skill, unused_skill.id)
    refute Repo.get(Item, unused_item.id)
  end

  test "a blocked cleanup deletion does not starve subsequent pages" do
    player = create_player!()
    protected = create_base_hero(%{archived_at: DateTime.add(DateTime.utc_now(), -8 * 86400)}, player)
    Accounts.set_online_now(Accounts.get_user!(player.user_id))
    # An archived hero still selected by a player is protected by its foreign key.
    others =
      for _ <- 1..25 do
        Game.create_hero!(
          %{name: "Old", archived_at: DateTime.add(DateTime.utc_now(), -8 * 86400)},
          player,
          base_avatar(),
          base_skills()
        )
      end

    log = ExUnit.CaptureLog.capture_log(fn -> Moba.Cleaner.cleanup_old_records() end)
    assert log =~ "Cleanup retained"
    assert Repo.get(Hero, protected.id)
    for hero <- others, do: refute(Repo.get(Hero, hero.id))
  end

  test "stale target refresh requests cannot reuse the last charge" do
    hero = create_base_hero(%{refresh_targets_count: 1})
    Game.refresh_targets!(hero)
    first = Game.list_targets(hero) |> Enum.map(& &1.id) |> Enum.sort()
    for _ <- 1..5, do: Game.refresh_targets!(hero)
    assert Game.get_hero!(hero.id).refresh_targets_count == 0
    assert Game.list_targets(hero) |> Enum.map(& &1.id) |> Enum.sort() == first
  end

  defp old_copy(resource, attrs \\ %{}) do
    schema = resource.__struct__
    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-8 * 86400) |> NaiveDateTime.truncate(:second)
    data = resource |> Map.from_struct() |> Map.take(schema.__schema__(:fields))

    data =
      Map.merge(data, %{id: nil, inserted_at: old, updated_at: old, current: false, resource_uuid: UUID.uuid1()})
      |> Map.merge(attrs)

    struct(schema, data) |> Repo.insert!()
  end
end
