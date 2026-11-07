defmodule Moba.Accounts.Unlocks do
  @moduledoc """
  Manages rewards that users can unlock by using shards
  """

  alias Moba.{Repo, Accounts, Game}
  alias Accounts.Schema.Unlock
  alias Accounts.Schema.User
  import Ecto.Query

  def buy_unlock!(user, %Game.Schema.Skill{}), do: Accounts.get_user_with_unlocks!(user.id)

  def buy_unlock!(user, resource) do
    {:ok, user} =
      Repo.transaction(fn ->
        stored = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE") |> Repo.preload(:unlocks)
        price = price_to_unlock(resource)
        owned? = Enum.any?(stored.unlocks, &(&1.resource_code == resource.code))

        if !owned? && stored.shard_count >= price do
          find_or_create!(stored.unlocks, %{user_id: stored.id, resource_code: resource.code})

          Accounts.update_user!(stored, %{shard_count: stored.shard_count - price})
          |> Repo.preload(:unlocks, force: true)
        else
          stored
        end
      end)

    user
  end

  def create_unlock!(user, resource_code) do
    {:ok, user} =
      Repo.transaction(fn ->
        stored = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE") |> Repo.preload(:unlocks)
        find_or_create!(stored.unlocks, %{user_id: stored.id, resource_code: resource_code})
        Repo.preload(stored, :unlocks, force: true)
      end)

    user
  end

  def unlocked_codes_for(user) do
    user = Repo.preload(user, :unlocks)
    Enum.map(user.unlocks, fn unlock -> unlock.resource_code end)
  end

  def price_to_unlock(%Game.Schema.Avatar{}), do: 150
  def price_to_unlock(%Game.Schema.Skill{}), do: 0
  def price_to_unlock(%Game.Schema.Skin{league_tier: 5}), do: 500
  def price_to_unlock(%Game.Schema.Skin{league_tier: 6}), do: 1000
  def price_to_unlock(_), do: 100

  defp find_or_create!(unlocks, attrs) do
    existing = Enum.find(unlocks, &(&1.resource_code == attrs[:resource_code]))

    if existing do
      existing
    else
      %Unlock{}
      |> Unlock.changeset(attrs)
      |> Repo.insert!()
    end
  end
end
