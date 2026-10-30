defmodule Moba.Accounts.ReturnCampaignTest do
  use Moba.DataCase, async: true

  import Moba.AccountsFixtures
  alias Moba.Accounts.{ReturnCampaign, UserToken}

  test "audience uses progression score, breaks ties by wins, and deduplicates users and emails" do
    first = user_fixture()
    second = user_fixture()
    duplicate = user_fixture(%{email: String.upcase(second.email)})
    first_player = create_player!(%{pve_tier: 3, pvp_points: 10, total_wins: 2}, first)
    create_player!(%{pvp_points: 5}, first)
    create_player!(%{pve_tier: 2, pvp_points: 110, total_wins: 1}, second)
    create_player!(%{pvp_points: 1}, duplicate)

    ids = [first.id, second.id, duplicate.id]
    contacts = ReturnCampaign.audience() |> Enum.filter(&(&1.user_id in ids))
    assert [%{user_id: first_id, player_id: player_id, score: 310}, %{user_id: second_id, score: 310}] = contacts
    assert first_id == first.id
    assert player_id == first_player.id
    assert second_id == second.id
  end

  test "excludes guests, bots, nonpositive scores, and suppressed addresses" do
    bot_user = user_fixture()
    zero = user_fixture()
    blocked = user_fixture()
    create_player!(%{pvp_points: 10}, bot_user, "bot")
    create_player!(%{pvp_points: 0}, zero)
    create_player!(%{pvp_points: 20}, blocked)
    Game.create_player!(%{pvp_points: 100})

    ids = [bot_user.id, zero.id, blocked.id]

    assert ReturnCampaign.audience(exclude_emails: [" #{String.upcase(blocked.email)} "])
           |> Enum.all?(&(&1.user_id not in ids))
  end

  test "preparation defaults to a private audience preview without creating tokens" do
    user = user_fixture()
    create_player!(%{pvp_points: 10}, user)
    path = output_path()
    before_count = Repo.aggregate(UserToken, :count)
    assert {:ok, %{tokens_issued: false}} = ReturnCampaign.prepare(path)
    payload = path |> File.read!() |> Jason.decode!()
    contact = Enum.find(payload["contacts"], &(&1["user_id"] == user.id))
    assert contact["username"] == user.username
    refute Map.has_key?(contact, "return_url")
    assert Repo.aggregate(UserToken, :count) == before_count
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert {:error, :eexist} = ReturnCampaign.prepare(path, issue_tokens: true)
    assert Repo.aggregate(UserToken, :count) == before_count
  end

  test "invitations are hashed, 30-day, nonconsuming on preview, and single use on redemption" do
    %{user: user, player: player, token: token} = invitation()
    stored = Repo.get_by!(UserToken, user_id: user.id)
    assert {:ok, decoded} = Base.url_decode64(token, padding: false)
    assert stored.token == :crypto.hash(:sha256, decoded)
    refute stored.token == decoded
    assert {:ok, %{id: id}} = ReturnCampaign.preview(token)
    assert id == user.id
    assert {:ok, _} = ReturnCampaign.preview(token)
    assert {:ok, %{user: %{id: ^id}, player_id: player_id}} = ReturnCampaign.redeem(token)
    assert player_id == player.id
    assert :error = ReturnCampaign.redeem(token)
    assert :error = ReturnCampaign.preview(token)
  end

  test "a second issuance refuses to invalidate existing campaign links" do
    %{token: token} = invitation()
    path = output_path()
    assert {:error, :campaign_tokens_already_exist} = ReturnCampaign.prepare(path, issue_tokens: true)
    refute File.exists?(path)
    assert {:ok, _} = ReturnCampaign.preview(token)
  end

  test "expires after 30 days" do
    %{user: user, token: token} = invitation()
    valid = NaiveDateTime.utc_now() |> NaiveDateTime.add(-29 * 86_400) |> NaiveDateTime.truncate(:second)
    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id), set: [inserted_at: valid])
    assert {:ok, _} = ReturnCampaign.preview(token)
    expired = NaiveDateTime.utc_now() |> NaiveDateTime.add(-30 * 86_400 - 1) |> NaiveDateTime.truncate(:second)
    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id), set: [inserted_at: expired])
    assert :error = ReturnCampaign.preview(token)
    assert :error = ReturnCampaign.redeem(token)
  end

  test "rejects invitations after a password or email change, including legacy update paths" do
    %{user: user, token: token} = invitation()
    changed = user |> Ecto.Changeset.change(email: "changed@example.com") |> Repo.update!()
    assert :error = ReturnCampaign.preview(token)
    changed |> Ecto.Changeset.change(email: user.email, hashed_password: "changed-credential") |> Repo.update!()
    assert :error = ReturnCampaign.preview(token)
    assert :error = ReturnCampaign.redeem(token)
  end

  test "redemption uses the account’s current role" do
    %{user: user, token: token} = invitation()
    user |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
    assert {:ok, %{is_admin: true}} = ReturnCampaign.preview(token)
    assert {:ok, %{user: %{is_admin: true}}} = ReturnCampaign.redeem(token)
  end

  test "rejects malformed input and other email-token contexts" do
    user = user_fixture()
    {token, stored} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(stored)

    for invalid <- [nil, %{}, [token], "", "not-a-token", String.duplicate("a", 500), token] do
      assert :error = ReturnCampaign.preview(invalid)
      assert :error = ReturnCampaign.redeem(invalid)
    end
  end

  test "admins use the same scoped export, 30-day token, and single-use redemption as other users" do
    user = user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
    player = create_player!(%{pvp_points: 10}, user)
    other = user_fixture()
    create_player!(%{pvp_points: 100}, other)
    assert Enum.any?(ReturnCampaign.audience(), &(&1.user_id == user.id))
    assert [%{user_id: selected_id}] = ReturnCampaign.audience(user_ids: [user.id])
    assert selected_id == user.id
    path = output_path()

    assert {:ok, %{count: 1, tokens_issued: true}} =
             ReturnCampaign.prepare(path, issue_tokens: true, user_ids: [user.id])

    payload = path |> File.read!() |> Jason.decode!()
    assert payload["campaign"] == "reborn_2026_10"
    [contact] = payload["contacts"]
    assert contact["user_id"] == user.id
    token = contact["return_url"] |> URI.parse() |> Map.fetch!(:fragment) |> URI.decode_query() |> Map.fetch!("token")
    valid = NaiveDateTime.utc_now() |> NaiveDateTime.add(-29 * 86_400) |> NaiveDateTime.truncate(:second)
    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id), set: [inserted_at: valid])
    assert {:ok, %{id: id, is_admin: true}} = ReturnCampaign.preview(token)
    assert id == user.id
    assert {:ok, %{user: %{id: ^id, is_admin: true}, player_id: player_id}} = ReturnCampaign.redeem(token)
    assert player_id == player.id
    assert :error = ReturnCampaign.redeem(token)
  end

  defp invitation do
    user = user_fixture()
    player = create_player!(%{pvp_points: 10}, user)
    path = output_path()
    assert {:ok, %{tokens_issued: true}} = ReturnCampaign.prepare(path, issue_tokens: true)
    payload = path |> File.read!() |> Jason.decode!()
    contact = Enum.find(payload["contacts"], &(&1["user_id"] == user.id))
    url = URI.parse(contact["return_url"])
    assert url.path == "/return"
    assert is_nil(url.query)
    token = URI.decode_query(url.fragment)["token"]
    %{user: user, player: player, token: token}
  end

  defp output_path do
    path = Path.join(System.tmp_dir!(), "moba-campaign-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
