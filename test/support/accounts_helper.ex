defmodule Test.AccountsHelper do
  alias Moba.Accounts

  def create_user(attrs \\ %{}) do
    name = Faker.Superhero.name()
    email = Faker.Internet.email()
    pass = "123456"

    creds = %{
      username: name,
      email: email,
      password: pass,
      confirm_password: pass
    }

    case Accounts.create_user(creds) do
      {:ok, user} -> user |> Accounts.update_user!(attrs)
      {:error, _} -> create_user(attrs)
    end
  end
end
