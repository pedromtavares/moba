defmodule MobaWeb.TavernView do
  alias Moba.Accounts
  alias MobaWeb.CreateView
  use MobaWeb, :view

  def unlocked?(resource, user) do
    user.unlocks
    |> Enum.map(fn unlock -> unlock.resource_code end)
    |> Enum.member?(resource.code)
  end

  def can_unlock?(resource, user) do
    user.level >= resource.level_requirement && user.shard_count >= price_to_unlock(resource)
  end

  def unlock_error_message(resource, user) do
    price = price_to_unlock(resource)

    cond do
      user.level < resource.level_requirement -> "This resource requires Account Level #{resource.level_requirement}"
      true -> "Not enough Shards to unlock (#{user.shard_count}/#{price})"
    end
  end

  def unlock_error_description(resource, user) do
    cond do
      user.level < resource.level_requirement -> "You can level your Account by leveling heroes in the Jungle"
      true -> "You can acquire Shards by leveling heroes in the Jungle or finishing in the top 3 of the Arena."
    end
  end

  def price_to_unlock(resource), do: Accounts.price_to_unlock(resource)
end
