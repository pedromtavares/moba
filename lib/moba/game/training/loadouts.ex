defmodule Moba.Game.Training.Loadouts do
  @moduledoc "Hero loadouts, progression and automatic purchasing for team training."
  alias Moba.{Game, Repo}
  alias Moba.Game.Schema.{Hero, Player}
  @rares ~w(vanguard maelstrom shadow_blade pipe_of_insight arcane_boots soul_booster)
  @max_level 30

  def catalog do
    avatars =
      Game.list_all_current_avatars()
      |> Enum.filter(&(&1.enabled && &1.code != "boss"))
      |> Repo.preload(:ultimate)
      |> Enum.sort_by(& &1.name)

    skills = Game.list_all_current_skills()

    %{
      avatars: avatars,
      items: Moba.cached_items(),
      skills: skills,
      builds: Map.new(avatars, &{&1.id, Game.Builds.training_build_for(&1, skills)})
    }
  end

  def max_hp(h), do: h.hero.total_hp + h.hero.item_hp
  def max_energy(h), do: h.hero.total_mp + h.hero.item_mp

  def xp_capacity(%{hero: %{level: level}}) when level >= @max_level, do: 0

  def xp_capacity(h) do
    required = Enum.sum(Enum.map((h.hero.level + 1)..@max_level, &Game.xp_to_next_hero_level/1))
    max(0, required - h.hero.experience)
  end

  def build_loadout(catalog, avatar, side, id, gold \\ 2000) do
    unit = spawn_hero(catalog, avatar, side, id)
    %{unit | hero: %{unit.hero | gold: gold}} |> auto_shop(catalog)
  end

  def grant_farm(h, gold, xp, catalog) do
    hero = %{
      h.hero
      | gold: h.hero.gold + gold,
        experience: h.hero.experience + xp,
        total_gold_farm: h.hero.total_gold_farm + gold,
        total_xp_farm: h.hero.total_xp_farm + xp
    }

    %{h | hero: hero} |> level_hero() |> auto_shop(catalog)
  end

  def automate_skills(h, catalog) do
    Enum.reduce(1..h.hero.skill_levels_available//1, h, fn _, current ->
      case Enum.find(current.hero.skills, &Game.can_level_skill?(current.hero, &1)) do
        nil -> current
        skill -> level_skill(current, skill.code, catalog)
      end
    end)
  end

  def configure(%{phase: :playing} = run, id, operation, value) do
    case run.heroes[id] do
      %{side: :radiant} = h ->
        updated =
          case operation do
            :auto_buy ->
              %{h | auto_buy: value == true}

            :skill ->
              level_skill(h, value, run.catalog)

            :buy ->
              buy_item(h, value, run.catalog)

            :sell ->
              sell_item(h, value)

            :transmute ->
              transmute(h, value, run.catalog)

            :orders ->
              hero_orders(h, value)

            :inventory_order ->
              inventory_order(h, value)

            _ ->
              h
          end

        put_in(run.heroes[id], updated)

      _ ->
        run
    end
  end

  def configure(run, _, _, _), do: run

  defp spawn_hero(catalog, avatar, side, id) do
    build = catalog.builds[avatar.id]
    skills = Enum.uniq_by(build.skills ++ List.wrap(avatar.ultimate), & &1.code)

    hero = %Hero{
      id: id,
      name: avatar.name,
      avatar: avatar,
      avatar_id: avatar.id,
      player: %Player{id: if(side == :radiant, do: -1, else: -2), current_immortal_streak: 0},
      skills: skills,
      items: [],
      level: 1,
      experience: 0,
      gold: 2000,
      pve_tier: 2,
      league_tier: 0,
      total_hp: avatar.total_hp,
      total_mp: avatar.total_mp,
      atk: avatar.atk,
      speed: avatar.speed,
      armor: avatar.armor,
      power: avatar.power,
      skill_order:
        if(side == :radiant,
          do: Game.Skills.default_skill_order(skills),
          else: Enum.filter(skills, &(!&1.passive)) |> Enum.map(& &1.code)
        ),
      item_order: [],
      inventory_order: []
    }

    %{
      id: id,
      side: side,
      hero: hero,
      hp: hero.total_hp,
      energy: hero.total_mp,
      auto_buy: true,
      auto_buy_opening_step: 0,
      inventory: [],
      final_build: build.items,
      deaths: 0,
      kills: 0
    }
  end

  defp hero_orders(h, orders) do
    skills =
      if orders["skill_order"],
        do: ordered_codes(orders["skill_order"], Enum.filter(h.hero.skills, &(!&1.passive))),
        else: h.hero.skill_order

    items =
      if orders["item_order"],
        do: ordered_codes(orders["item_order"], Enum.filter(h.hero.items, & &1.active)),
        else: h.hero.item_order

    %{h | hero: %{h.hero | skill_order: skills, item_order: items}}
  end

  defp inventory_order(h, codes) when is_list(codes) do
    if Enum.sort(codes) == Enum.sort(Enum.map(h.hero.items, & &1.code)) do
      active = Enum.map(Enum.filter(h.hero.items, & &1.active), & &1.code)
      %{h | hero: %{h.hero | inventory_order: codes, item_order: Enum.filter(codes, &(&1 in active))}}
    else
      h
    end
  end

  defp inventory_order(h, _), do: h

  defp ordered_codes(params, resources) do
    allowed = Enum.map(resources, & &1.code)

    selected =
      params
      |> Enum.filter(fn {code, _} -> code in allowed end)
      |> Enum.sort_by(fn {_, rank} -> parse_rank(rank) end)
      |> Enum.map(&elem(&1, 0))

    Enum.uniq(selected ++ allowed)
  end

  defp parse_rank(value) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      _ -> 99
    end
  end

  defp level_skill(h, code, catalog) do
    current = Enum.find(h.hero.skills, &(&1.code == code))
    next = current && Enum.find(catalog.skills, &(&1.code == code && &1.level == current.level + 1))

    if current && next && Game.can_level_skill?(h.hero, current) do
      %{
        h
        | hero: %{
            h.hero
            | skills: Enum.map(h.hero.skills, fn s -> if s.code == code, do: next, else: s end),
              skill_levels_available: h.hero.skill_levels_available - 1
          }
      }
    else
      h
    end
  end

  defp buy_item(h, code, catalog) do
    item = Enum.find(catalog.items, &(&1.code == code))

    if item && length(h.inventory) < 6 && !Enum.any?(h.inventory, &(&1.item.code == code)) &&
         h.hero.gold >= Game.item_price(item) do
      price = Game.item_price(item)
      entry = %{item: item}
      sync_inventory(%{h | hero: %{h.hero | gold: h.hero.gold - price}}, h.inventory ++ [entry])
    else
      h
    end
  end

  defp sell_item(h, code) do
    case Enum.find(h.inventory, &(&1.item.code == code)) do
      nil ->
        h

      %{item: item} ->
        sync_inventory(
          %{h | hero: %{h.hero | gold: h.hero.gold + Game.item_sell_price(h.hero, item)}},
          Enum.reject(h.inventory, &(&1.item.code == code))
        )
    end
  end

  defp transmute(h, %{"transmute_code" => code, "recipe_codes" => codes}, catalog) when is_list(codes) do
    result = Enum.find(catalog.items, &(&1.code == code))
    ingredients = Enum.filter(h.inventory, &(&1.item.code in codes))

    valid =
      result && result.rarity != "normal" && length(codes) == length(Enum.uniq(codes)) &&
        length(ingredients) == Game.item_ingredients_count(result) &&
        length(codes) == length(ingredients) && !Enum.any?(h.inventory, &(&1.item.code == code)) &&
        Enum.all?(ingredients, &(&1.item.rarity == Game.previous_item_rarity(result)))

    if valid do
      entry = %{item: result}
      sync_inventory(h, Enum.reject(h.inventory, &(&1 in ingredients)) ++ [entry])
    else
      h
    end
  end

  defp transmute(h, _, _), do: h

  defp sync_inventory(h, entries) do
    items = Enum.map(entries, & &1.item)
    attrs = Game.Items.item_attributes(items)
    hero = struct(h.hero, attrs)
    codes = Enum.map(items, & &1.code)
    saved = Enum.filter(h.hero.inventory_order, &(&1 in codes))
    active = Enum.map(Enum.filter(items, & &1.active), & &1.code)
    saved_active = Enum.filter(h.hero.item_order, &(&1 in active))

    hero = %{
      hero
      | items: items,
        inventory_order: saved ++ (codes -- saved),
        item_order: saved_active ++ (active -- saved_active)
    }

    %{
      h
      | hero: hero,
        inventory: entries,
        hp: round(h.hp * (hero.total_hp + hero.item_hp) / max(1, max_hp(h))),
        energy: round(h.energy * (hero.total_mp + hero.item_mp) / max(1, max_energy(h)))
    }
  end

  defp auto_shop(%{auto_buy: false} = h, _), do: h

  defp auto_shop(h, catalog) do
    {step, opening_item} = next_opening_item(h, catalog)
    h = Map.put(h, :auto_buy_opening_step, step)

    missing =
      opening_item ||
        Enum.find_value(
          Enum.uniq(h.final_build ++ @rares ++ Enum.map(Enum.filter(catalog.items, &(&1.rarity == "rare")), & &1.code)),
          &missing_rare(h, catalog, &1)
        )

    cond do
      length(h.inventory) < 6 && missing && h.hero.gold >= Game.item_price(missing) ->
        step = if opening_item, do: step + 1, else: step

        h
        |> Map.put(:auto_buy_opening_step, step)
        |> buy_item(missing.code, catalog)
        |> auto_shop(catalog)

      # The boots limit can exhaust useful rares before all six slots are filled.
      length(h.inventory) == 6 || is_nil(missing) ->
        auto_upgrade(h, catalog)

      true ->
        h
    end
  end

  defp next_opening_item(h, catalog) do
    codes = if h.hero.avatar.role == "nuker", do: ~w(tranquil_boots vanguard), else: ~w(arcane_boots shadow_blade)

    # Older runs recorded only whether the first automatic purchase had happened.
    step = Map.get(h, :auto_buy_opening_step, if(Map.get(h, :auto_bought_item, false), do: 1, else: 0))

    codes
    |> Enum.with_index()
    |> Enum.drop(step)
    |> Enum.find_value({length(codes), nil}, fn {code, index} ->
      if item = missing_rare(h, catalog, code), do: {index, item}
    end)
  end

  defp missing_rare(h, catalog, code) do
    item = Enum.find(catalog.items, &(&1.code == code))

    if item && item.rarity == "rare" && !Enum.any?(h.inventory, &(&1.item.code == code)) &&
         auto_item_allowed?(h.inventory, item),
       do: item
  end

  defp auto_item_allowed?(inventory, item) do
    !Game.Items.boots?(item) || !Enum.any?(inventory, &Game.Items.boots?(&1.item))
  end

  defp auto_upgrade(h, catalog) do
    target =
      Enum.find_value(h.final_build, fn code ->
        item = Enum.find(catalog.items, &(&1.code == code))

        if item && item.rarity in ["epic", "legendary"] && !Enum.any?(h.inventory, &(&1.item.code == code)) do
          ingredients =
            Enum.filter(
              h.inventory,
              &(&1.item.rarity == Game.previous_item_rarity(item) && &1.item.code not in h.final_build)
            )
            |> Enum.take(2)

          if length(ingredients) == 2 && auto_item_allowed?(h.inventory -- ingredients, item),
            do: {item, ingredients}
        end
      end)

    case target do
      {item, ingredients} ->
        changed =
          transmute(
            h,
            %{"transmute_code" => item.code, "recipe_codes" => Enum.map(ingredients, & &1.item.code)},
            catalog
          )

        auto_shop(changed, catalog)

      nil ->
        # Intermediate epics are needed for a legendary even when not part of the final build.
        rares =
          Enum.filter(h.inventory, &(&1.item.rarity == "rare" && &1.item.code not in h.final_build)) |> Enum.take(2)

        legendary_missing =
          Enum.any?(
            catalog.items,
            &(&1.code in h.final_build && &1.rarity == "legendary" &&
                !Enum.any?(h.inventory, fn e -> e.item.code == &1.code end))
          )

        intermediate =
          Enum.find(
            catalog.items,
            &(&1.rarity == "epic" && !Enum.any?(h.inventory, fn e -> e.item.code == &1.code end) &&
                auto_item_allowed?(h.inventory -- rares, &1))
          )

        if legendary_missing && intermediate && length(rares) == 2 do
          auto_shop(
            transmute(
              h,
              %{"transmute_code" => intermediate.code, "recipe_codes" => Enum.map(rares, & &1.item.code)},
              catalog
            ),
            catalog
          )
        else
          h
        end
    end
  end

  defp level_hero(h) do
    cost = Game.xp_to_next_hero_level(h.hero.level + 1)

    if h.hero.experience >= cost && h.hero.level < @max_level do
      old = h.hero

      hero =
        old
        |> Ecto.Changeset.change()
        |> Hero.level_up(old.level, old.experience - cost)
        |> Ecto.Changeset.apply_changes()

      level_hero(%{
        h
        | hero: hero,
          hp: round(h.hp * (hero.total_hp + hero.item_hp) / max_hp(h)),
          energy: round(h.energy * (hero.total_mp + hero.item_mp) / max(1, max_energy(h)))
      })
    else
      h
    end
  end
end
