defmodule Moba.SiteSettings do
  alias Moba.Accounts.Schema.User
  alias Moba.Repo
  alias Moba.SiteSettings.Setting

  def get, do: Repo.get!(Setting, 1)

  def change(attrs \\ %{}), do: Setting.changeset(get(), attrs)

  def update(%User{is_admin: true}, attrs), do: get() |> Setting.changeset(attrs) |> Repo.update()
  def update(_, _attrs), do: {:error, :unauthorized}
end
