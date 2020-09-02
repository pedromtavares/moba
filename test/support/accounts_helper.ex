defmodule Test.AccountsHelper do
  alias Moba.Accounts

  def create_bot(pvp_points \\ 0), do: create_user(%{pvp_points: pvp_points}, true)

  def create_guest, do: create_user(%{}, false, true)

  def create_user(attrs \\ %{}, is_bot \\ false, is_guest \\ false) do
    name = Faker.Superhero.name()
    email = Faker.Internet.email()
    pass = "123456"

    creds = %{
      username: name,
      email: email,
      password: pass,
      confirm_password: pass,
      is_bot: is_bot,
      is_guest: is_guest
    }

    case Accounts.create_user(creds) do
      {:ok, user} -> user |> Accounts.update_user!(attrs)
      {:error, _} -> create_user(attrs)
    end
  end
end
