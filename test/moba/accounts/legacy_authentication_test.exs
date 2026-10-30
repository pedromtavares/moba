defmodule Moba.Accounts.LegacyAuthenticationTest do
  use Moba.DataCase, async: true

  import Moba.AccountsFixtures

  alias Moba.Accounts.{LegacyPassword, UserToken}
  alias Moba.Accounts.Schema.User

  @legacy_password "legacy password123"
  # Pow-format PBKDF2-SHA512 fixture generated independently with Python's
  # hashlib.pbkdf2_hmac (1,000 iterations, 64-byte key).
  @legacy_hash "pbkdf2-sha512$1000$cG93LWNvbXBhdGliaWxpdHktdGVzdC1zYWx0$L3DB02mxri8AzMjKySY1fF57ViQpisOXmOFwGkDFkeDUk68r1JwG37GUghqMTHN7UaOKpI84Z71RFmSvPUcW4Q=="

  test "an incorrect password leaves the legacy credentials intact" do
    user = legacy_user()
    refute Accounts.get_user_by_email_and_password(user.email, "incorrect password")
    persisted = Repo.get!(User, user.id)
    assert persisted.password_hash == @legacy_hash
    assert is_nil(persisted.hashed_password)
  end

  test "existing Pow passwords still log in and continue working after the hash upgrade" do
    user = legacy_user()
    authenticated = Accounts.get_user_by_email_and_password(user.email, @legacy_password)
    assert authenticated.id == user.id
    assert is_nil(authenticated.password_hash)
    assert User.valid_password?(authenticated, @legacy_password)
    persisted = Repo.get!(User, user.id)
    assert is_nil(persisted.password_hash)
    assert persisted.hashed_password == authenticated.hashed_password
    assert Accounts.get_user_by_email_and_password(user.email, @legacy_password).id == user.id
    refute Accounts.get_user_by_email_and_password(user.email, "incorrect password")
  end

  test "resetting an untouched legacy account replaces the old password and revokes sessions" do
    user = legacy_user()
    Accounts.generate_user_session_token(user)
    assert {:ok, updated} = Accounts.reset_user_password(user, %{password: "new valid password"})
    assert is_nil(updated.password_hash)
    refute Repo.get_by(UserToken, user_id: user.id)
    refute Accounts.get_user_by_email_and_password(user.email, @legacy_password)
    assert Accounts.get_user_by_email_and_password(user.email, "new valid password").id == user.id
    assert is_nil(Repo.get!(User, user.id).password_hash)
  end

  test "a rejected reset preserves the original legacy password" do
    user = legacy_user()
    assert {:error, _changeset} = Accounts.reset_user_password(user, %{password: "short"})
    persisted = Repo.get!(User, user.id)
    assert persisted.password_hash == @legacy_hash
    assert is_nil(persisted.hashed_password)
    assert LegacyPassword.verify(@legacy_password, persisted.password_hash)
  end

  test "new accounts use bcrypt without creating a legacy hash" do
    user = user_fixture()
    assert is_nil(user.password_hash)
    assert User.valid_password?(user, valid_user_password())
  end

  defp legacy_user do
    user_fixture()
    |> Ecto.Changeset.change(hashed_password: nil, password_hash: @legacy_hash)
    |> Repo.update!()
  end
end
