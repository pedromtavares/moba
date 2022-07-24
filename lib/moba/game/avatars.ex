defmodule Moba.Game.Avatars do
  @moduledoc """
  Manages Avatar records and queries.
  See Moba.Game.Schema.Avatar for more info.

  Avatars have 4 'virtual' display attributes that makes it easier for
  new players to distinguish their gameplay style. These are calculated
  relatively based on the minimum of a stat that an Avatar can have as
  well as a unit of value for each stat.
  Example: 1 ATK can be loosely translated to 5 HP and 4 MP, and the
  lowest ATK any Avatar can have is 12.
  By using these measures and real stats from Avatars, we can generate
  progress bars of how much Offense, Defense, Speed and Magic each Avatar
  has in relation to other Avatars.
  You can see this in action by heading to /start route.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Avatar
  alias Game.Query.AvatarQuery

  # -------------------------------- PUBLIC API

  def avatar_minimum_stats do
    %{
      total_hp: 200,
      total_mp: 10,
      atk: 12,
      power: 0,
      armor: 0,
      speed: 0
    }
  end

  def avatar_stat_units do
    %{
      total_hp: 5,
      total_mp: 4,
      atk: 1,
      power: 1.4,
      armor: 1,
      speed: 5
    }
  end

  def boss!, do: Repo.get_by!(Avatar, code: "boss")

  def create_avatar!(%Avatar{} = avatar, attrs) do
    ultimate_code = Map.get(avatar, :ultimate_code) || attrs["ultimate_code"]
    ultimate = ultimate_code && Game.get_skill_by_code!(ultimate_code, avatar.current)

    avatar
    |> Avatar.create_changeset(attrs, ultimate)
    |> Repo.insert!()
  end

  def get_avatar!(nil), do: nil
  def get_avatar!(""), do: nil
  def get_avatar!(id), do: Repo.get!(Avatar, id) |> Repo.preload(:ultimate) |> with_extra_stats()
  def get_avatar_by_code!(code), do: unlocked_list([code]) |> List.first()

  def list_avatars, do: AvatarQuery.base_canon() |> Repo.all() |> with_extra_stats()

  def list_creation_avatars(codes) do
    base_list = AvatarQuery.base_current() |> Repo.all()

    (unlocked_list(codes) ++ base_list)
    |> Repo.preload(:ultimate)
    |> with_extra_stats()
  end

  def list_unlockable_avatars do
    AvatarQuery.canon()
    |> AvatarQuery.enabled()
    |> AvatarQuery.with_level_requirement()
    |> Repo.all()
    |> Repo.preload(:ultimate)
    |> with_extra_stats()
  end

  # --------------------------------

  defp with_extra_stats(avatars) when is_list(avatars) do
    Enum.map(avatars, fn avatar -> with_extra_stats(avatar) end)
  end

  defp with_extra_stats(%Avatar{} = avatar) do
    minimum = avatar_minimum_stats()
    units = avatar_stat_units()

    Map.merge(avatar, %{
      display_defense:
        (avatar.total_hp - minimum[:total_hp]) / units[:total_hp] + (avatar.armor - minimum[:armor]) / units[:armor],
      display_offense: (avatar.atk - minimum[:atk]) / units[:atk] + (avatar.power - minimum[:power]) / units[:power],
      display_magic: (avatar.total_mp - minimum[:total_mp]) / units[:total_mp],
      display_speed: (avatar.speed - minimum[:speed]) / units[:speed]
    })
  end

  defp unlocked_list(codes) when length(codes) > 0 do
    AvatarQuery.all_current()
    |> AvatarQuery.with_codes(codes)
    |> Repo.all()
  end

  defp unlocked_list(_), do: []
end
