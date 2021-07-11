defmodule MobaWeb.TavernView do
  use MobaWeb, :view

  alias MobaWeb.CreateView

  def unlocked?(resource, user) do
    user.unlocks
    |> Enum.map(fn unlock -> unlock.resource_code end)
    |> Enum.member?(resource.code)
  end

  def can_unlock?(%Game.Schema.Skin{league_tier: league_tier, avatar_code: avatar_code} = resource, user) do
    has_hero_in_collection?(avatar_code, league_tier, user) && has_enough_shards?(resource, user)
  end

  def can_unlock?(resource, user), do: has_enough_shards?(resource, user)

  def unlock_error_message(%Game.Schema.Skin{league_tier: league_tier, avatar_code: avatar_code} = resource, user) do
    if has_enough_shards?(resource, user) do
      league = Moba.leagues()[league_tier]
      avatar = Game.get_avatar_by_code!(avatar_code)
      "You need to have #{avatar.name} in the #{league} to unlock this Skin"
    else
      price_error_message(resource, user)
    end
  end

  def unlock_error_message(resource, user), do: price_error_message(resource, user)

  def price_to_unlock(resource), do: Accounts.price_to_unlock(resource)

  defp has_hero_in_collection?(avatar_code, league_tier, %{hero_collection: collection}) do
    Enum.find(collection, fn %{"code" => code, "tier" => tier} ->
      avatar_code == code && tier >= league_tier
    end)
  end

  defp has_enough_shards?(resource, user), do: user.shard_count >= price_to_unlock(resource)

  defp price_error_message(resource, user) do
    price = price_to_unlock(resource)
    "Not enough Shards to unlock (#{user.shard_count}/#{price})"
  end
end
