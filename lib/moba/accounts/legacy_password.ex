defmodule Moba.Accounts.LegacyPassword do
  @moduledoc """
  Verifies password hashes created by Pow's pbkdf2 implementation.

  Kept here so Pow can be removed as a dependency while still being able to
  verify existing user passwords during the on-login migration to bcrypt.
  Once all users have logged in at least once after the migration, this module
  and its Pbkdf2 submodule can be deleted.
  """

  alias Moba.Accounts.LegacyPassword.Pbkdf2

  @doc """
  Returns true if the plain-text password matches a Pow-generated pbkdf2 hash.
  """
  @spec verify(binary(), binary()) :: boolean()
  def verify(password, hash) when is_binary(password) and is_binary(hash) do
    hash
    |> decode()
    |> do_verify(password)
  end

  defp decode(hash) do
    case String.split(hash, "$", trim: true) do
      ["pbkdf2-" <> digest, iterations, salt, hash] ->
        {:ok, salt} = Base.decode64(salt)
        {:ok, hash} = Base.decode64(hash)
        digest = String.to_existing_atom(digest)
        iterations = String.to_integer(iterations)
        {digest, iterations, salt, hash}

      _ ->
        :invalid
    end
  end

  defp do_verify(:invalid, _password), do: false

  defp do_verify({digest, iterations, salt, hash}, password) do
    secret_hash = Pbkdf2.generate(password, salt, iterations, 64, digest)
    Pbkdf2.compare(hash, secret_hash)
  end
end
