defmodule Moba.Admin.Seasons do
  @moduledoc """
  Admin functions for managing Seasons, mostly generated by Torch package.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Season
  alias Game.Query.{PlayerQuery, HeroQuery, SkillQuery}

  import Ecto.Query
  import Torch.Helpers, only: [sort: 1, paginate: 4]
  import Filtrex.Type.Config

  @pagination [page_size: 50]
  @pagination_distance 5

  def paginate(params \\ %{}) do
    params =
      params
      |> Map.put_new("sort_direction", "desc")
      |> Map.put_new("sort_field", "inserted_at")

    {:ok, sort_direction} = Map.fetch(params, "sort_direction")
    {:ok, sort_field} = Map.fetch(params, "sort_field")

    with {:ok, filter} <- Filtrex.parse_params(filter_config(:seasons), params["season"] || %{}),
         %Scrivener.Page{} = page <- do_paginate(filter, params) do
      {:ok,
       %{
         seasons: page.entries,
         page_number: page.page_number,
         page_size: page.page_size,
         total_pages: page.total_pages,
         total_entries: page.total_entries,
         distance: @pagination_distance,
         sort_field: sort_field,
         sort_direction: sort_direction
       }}
    else
      {:error, error} -> {:error, error}
      error -> {:error, error}
    end
  end

  def list do
    Repo.all(Season)
  end

  def list_recent do
    Repo.all(from m in Season, limit: 10, order_by: [desc: m.id])
  end

  def get!(id), do: Repo.get!(Season, id)

  def update(%Season{} = season, attrs) do
    season
    |> Season.changeset(attrs)
    |> Repo.update()
  end

  def change(%Season{} = season) do
    Season.changeset(season, %{})
  end

  def current_active_players do
    PlayerQuery.non_bots()
    |> PlayerQuery.non_guests()
    |> PlayerQuery.currently_active()
    |> Repo.all()
    |> Repo.preload(:user)
    |> Enum.map(fn player ->
      heroes = HeroQuery.latest(player.id, 5) |> HeroQuery.load_avatar() |> Repo.all()

      count = HeroQuery.with_player(HeroQuery.unarchived(), player.id) |> Repo.aggregate(:count)

      player
      |> Map.put(:latest_heroes, heroes)
      |> Map.put(:hero_count, count)
    end)
  end

  def current_guests do
    PlayerQuery.non_bots()
    |> PlayerQuery.guests()
    |> PlayerQuery.recently_created()
    |> Repo.all()
    |> Repo.preload(current_pve_hero: [:avatar, :items, skills: SkillQuery.ordered()])
    |> Enum.filter(& &1.current_pve_hero)
    |> Enum.sort_by(& &1.current_pve_hero.league_tier, :desc)
  end

  defp do_paginate(filter, params) do
    Season
    |> Filtrex.query(filter)
    |> order_by(^sort(params))
    |> paginate(Repo, params, @pagination)
  end

  defp filter_config(:seasons) do
    defconfig do
      text(:changelog)
      boolean(:active)
    end
  end
end
