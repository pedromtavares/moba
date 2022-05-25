defmodule Moba.Accounts.Unlocks do
  @moduledoc """
  Manages rewards that users can unlock by using shards
  """

  alias Moba.{Repo, Accounts, Game}
  alias Accounts.Schema.Unlock

  def create_unlock!(%{shard_count: shard_count} = user, resource) do
    user = Repo.preload(user, :unlocks)
    price = price_to_unlock(resource)

    if shard_count >= price do
      unlock = do_create!(%{user_id: user.id, resource_code: resource.code})
      user = Accounts.update_user!(user, %{shard_count: shard_count - price})
      %{user | unlocks: user.unlocks ++ [unlock]}
    else
      user
    end
  end

  def unlocked_codes_for(user) do
    user = Repo.preload(user, :unlocks)
    Enum.map(user.unlocks, fn unlock -> unlock.resource_code end)
  end

  def price_to_unlock(%Game.Schema.Avatar{}), do: 150
  def price_to_unlock(%Game.Schema.Skill{}), do: 100
  def price_to_unlock(%Game.Schema.Skin{league_tier: 5}), do: 500
  def price_to_unlock(%Game.Schema.Skin{league_tier: 6}), do: 1000
  def price_to_unlock(_), do: 100

  defp do_create!(attrs) do
    %Unlock{}
    |> Unlock.changeset(attrs)
    |> Repo.insert!()
  end
end
