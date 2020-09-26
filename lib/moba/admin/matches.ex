defmodule Moba.Admin.Matches do
  @moduledoc """
  Admin functions for managing Matches, mostly generated by Torch package.
  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.Schema.Match
  alias Game.Query.HeroQuery
  alias Accounts.Query.UserQuery

  import Ecto.Query, warn: false
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

    with {:ok, filter} <- Filtrex.parse_params(filter_config(:matches), params["match"] || %{}),
         %Scrivener.Page{} = page <- do_paginate(filter, params) do
      {:ok,
       %{
         matches: page.entries,
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
    Repo.all(Match)
  end

  def list_recent do
    Repo.all(from m in Match, limit: 10, order_by: [desc: m.id])
  end

  def get!(id), do: Repo.get!(Match, id)

  def update(%Match{} = match, attrs) do
    match
    |> Match.changeset(attrs)
    |> Repo.update()
  end

  def change(%Match{} = match) do
    Match.changeset(match, %{})
  end

  def recent_winrates(match_time) do
    HeroQuery.pvp_picked_recently(match_time)
    |> Repo.all()
    |> Repo.preload(active_build: [:skills])
    |> skill_winrates()
    |> Map.new(fn {_key, {skill, list}} ->
      count = Enum.count(list)
      {skill, {Enum.sum(list) / count, count}}
    end)
  end

  def current_arena_heroes do
    HeroQuery.pvp_active()
    |> Repo.all()
    |> Repo.preload([:avatar, :items, :user, active_build: [skills: Game.ordered_skills_query()]])
    |> Enum.sort_by(fn hero -> [hero.pvp_ranking] end)
  end

  def current_active_players do
    UserQuery.current_players()
    |> UserQuery.non_bots()
    |> UserQuery.non_guests()
    |> UserQuery.online_users(24)
    |> Repo.all()
    |> Enum.map(fn user ->
      Map.put(user, :current_hero, Game.current_hero(user))
    end)
  end

  defp skill_winrates(heroes) do
    heroes
    |> Enum.reduce([], fn hero, acc ->
      winrate = Game.pvp_win_rate(hero)

      if winrate == 0 do
        acc
      else
        rates =
          hero.active_build.skills
          |> Enum.map(fn skill ->
            {skill.code, skill, winrate}
          end)

        acc ++ rates
      end
    end)
    |> Enum.reduce(%{}, fn {code, skill, rate}, acc ->
      {_, list} = Map.get(acc, code) || {skill, []}
      Map.put(acc, code, {skill, [rate | list]})
    end)
  end

  defp do_paginate(filter, params) do
    Match
    |> Filtrex.query(filter)
    |> order_by(^sort(params))
    |> paginate(Repo, params, @pagination)
  end

  defp filter_config(:matches) do
    defconfig do
      text(:next_changelog)
    end
  end
end
