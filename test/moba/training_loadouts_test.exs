defmodule Moba.Game.Training.LoadoutsTest do
  use Moba.DataCase, async: true
  alias Moba.Game.Training.Loadouts

  setup do
    catalog = Loadouts.catalog()
    hero = Loadouts.build_loadout(catalog, hd(catalog.avatars), :radiant, 1)
    %{run: %{phase: :playing, heroes: %{1 => hero}, catalog: catalog}, catalog: catalog}
  end

  test "catalog loading uses bounded queries and keeps every avatar's exact default build" do
    counter = :atomics.new(1, [])
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:moba, :repo, :query],
        fn _, _, _, _ ->
          if self() == owner, do: :atomics.add(counter, 1, 1)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    catalog = Loadouts.catalog()
    assert :atomics.get(counter, 1) <= 8
    :telemetry.detach(handler)

    for avatar <- catalog.avatars do
      assert catalog.builds[avatar.id] == Game.Builds.training_build_for(avatar)
    end
  end

  test "every avatar buys its role's two opening rares before following its build", %{catalog: catalog} do
    price = Moba.rare_items_price()

    for avatar <- catalog.avatars, tier <- [0, Moba.max_pve_tier()] do
      [boots, second] = if avatar.role == "nuker", do: ~w(tranquil_boots vanguard), else: ~w(arcane_boots shadow_blade)
      hero = Loadouts.build_loadout(catalog, avatar, :radiant, 1, Moba.initial_gold(%{pve_tier: tier}))
      hero = %{hero | hero: %{hero.hero | pve_tier: tier}, final_build: ~w(maelstrom pipe_of_insight)}
      assert Enum.map(hero.inventory, & &1.item.code) == [boots]

      hero = Loadouts.grant_farm(hero, price - hero.hero.gold, 0, catalog)
      assert Enum.map(hero.inventory, & &1.item.code) == [boots, second]
      assert hero.hero.gold == 0

      hero = Loadouts.grant_farm(hero, price, 0, catalog)
      assert Enum.map(hero.inventory, & &1.item.code) == [boots, second, "maelstrom"]
    end
  end

  test "a saved run applies the second priority and does not restart the opening after a sale", %{catalog: catalog} do
    avatar = Enum.find(catalog.avatars, &(&1.role == "nuker"))
    price = Moba.rare_items_price()

    hero =
      Loadouts.build_loadout(catalog, avatar, :radiant, 1, price)
      |> Map.delete(:auto_buy_opening_step)
      |> Map.put(:auto_bought_item, true)
      |> Map.put(:final_build, ~w(maelstrom pipe_of_insight))

    hero = Loadouts.grant_farm(hero, price, 0, catalog)
    assert Enum.map(hero.inventory, & &1.item.code) == ~w(tranquil_boots vanguard)

    run = %{phase: :playing, heroes: %{1 => hero}, catalog: catalog}
    sold = Loadouts.configure(run, 1, :sell, "vanguard").heroes[1]
    hero = Loadouts.grant_farm(sold, 0, 0, catalog)
    assert Enum.map(hero.inventory, & &1.item.code) == ~w(tranquil_boots maelstrom)
  end

  test "auto-buy skips extra boots and keeps upgrading after useful rares run out", %{run: b} do
    boots = ~w(arcane_boots tranquil_boots phase_boots boots_of_travel boots_of_speed)

    for existing <- [nil, "tranquil_boots"] do
      run = Loadouts.configure(b, 1, :sell, hd(b.heroes[1].inventory).item.code)

      run =
        run
        |> then(&put_in(&1.heroes[1].hero.gold, 7200))
        |> put_in([:heroes, 1, :final_build], ["arcane_boots", "tranquil_boots", "satanic"])

      run = if existing, do: Loadouts.configure(run, 1, :buy, existing), else: run
      run = update_in(run.heroes[1], &Loadouts.grant_farm(&1, 0, 0, run.catalog))
      hero = run.heroes[1]
      assert length(hero.inventory) == 5
      assert hero.hero.gold == 0
      assert Enum.any?(hero.hero.items, &(&1.rarity == "epic" && &1.code not in boots))
      assert Enum.map(Enum.filter(hero.hero.items, &(&1.code in boots)), & &1.code) == [existing || "arcane_boots"]
    end
  end

  test "automatic transmutation never adds another pair of boots but can consume boots in an upgrade", %{
    run: b,
    catalog: catalog
  } do
    boots = ~w(arcane_boots tranquil_boots phase_boots boots_of_travel boots_of_speed)
    phase = Enum.find(catalog.items, &(&1.code == "phase_boots"))
    catalog = %{catalog | items: [phase | Enum.reject(catalog.items, &(&1.code == phase.code))]}

    for {build, expected} <- [
          {["arcane_boots", "phase_boots"], "arcane_boots"},
          {["arcane_boots", "boots_of_travel"], "arcane_boots"},
          {["phase_boots"], "phase_boots"}
        ] do
      run = Loadouts.configure(b, 1, :sell, hd(b.heroes[1].inventory).item.code)

      run =
        %{run | catalog: catalog}
        |> then(&put_in(&1.heroes[1].hero.gold, 7200))
        |> put_in([:heroes, 1, :final_build], build)

      run =
        Enum.reduce(~w(arcane_boots vanguard maelstrom shadow_blade pipe_of_insight magic_stick), run, fn code, acc ->
          Loadouts.configure(acc, 1, :buy, code)
        end)

      run = update_in(run.heroes[1], &Loadouts.grant_farm(&1, 0, 0, run.catalog))
      assert Enum.map(Enum.filter(run.heroes[1].hero.items, &(&1.code in boots)), & &1.code) == [expected]

      if build == ["arcane_boots", "boots_of_travel"] do
        assert Enum.any?(run.heroes[1].hero.items, &(&1.rarity == "epic" && &1.code not in boots))
      end
    end
  end

  test "sales after transmutation refund the full price without changing farm or auto-buy", %{run: b, catalog: c} do
    b = put_in(b.heroes[1].hero.total_gold_farm, 6000)
    b = put_in(b.heroes[1].hero.total_xp_farm, 6000)
    h = b.heroes[1]
    first = hd(h.inventory).item
    b = Loadouts.configure(b, 1, :sell, first.code)
    assert b.heroes[1].hero.gold == 2000
    b = put_in(b.heroes[1].hero.gold, 10_000)
    rares = c.items |> Enum.filter(&(&1.rarity == "rare" && &1.code != first.code)) |> Enum.take(2)
    b = Enum.reduce(rares, b, fn item, b -> Loadouts.configure(b, 1, :buy, item.code) end)
    assert b.heroes[1].auto_buy
    epic = Enum.find(c.items, &(&1.rarity == "epic"))

    b =
      Loadouts.configure(b, 1, :transmute, %{
        "transmute_code" => epic.code,
        "recipe_codes" => Enum.map(rares, & &1.code)
      })

    before = b.heroes[1].hero.gold
    b = Loadouts.configure(b, 1, :sell, epic.code)
    assert b.heroes[1].hero.gold == before + Game.item_price(epic)
    assert b.heroes[1].hero.total_gold_farm == 6000
    assert b.heroes[1].hero.total_xp_farm == 6000
    assert b.heroes[1].auto_buy
  end

  test "a mixed recipe refunds the full item price", %{run: b, catalog: c} do
    automatic = hd(b.heroes[1].inventory).item
    manual = Enum.find(c.items, &(&1.rarity == "rare" && &1.code != automatic.code))
    epic = Enum.find(c.items, &(&1.rarity == "epic"))
    b = put_in(b.heroes[1].hero.gold, 1200)
    b = Loadouts.configure(b, 1, :buy, manual.code)

    b =
      Loadouts.configure(b, 1, :transmute, %{
        "transmute_code" => epic.code,
        "recipe_codes" => [automatic.code, manual.code]
      })

    assert b.heroes[1].auto_buy
    b = Loadouts.configure(b, 1, :sell, epic.code)
    assert b.heroes[1].hero.gold == Game.item_price(epic)
  end

  test "inventory changes preserve manual combat and inventory orders", %{run: b, catalog: c} do
    skills = b.heroes[1].hero.skill_order |> Enum.reverse()
    order = Map.new(Enum.with_index(skills), fn {code, i} -> {code, to_string(i)} end)
    b = Loadouts.configure(b, 1, :orders, %{"skill_order" => order})
    b = put_in(b.heroes[1].hero.gold, 20_000)
    items = Enum.reject(c.items, &(&1.code in Enum.map(b.heroes[1].hero.items, fn i -> i.code end))) |> Enum.take(2)
    b = Enum.reduce(items, b, fn item, b -> Loadouts.configure(b, 1, :buy, item.code) end)
    inventory = b.heroes[1].hero.items |> Enum.map(& &1.code) |> Enum.reverse()
    b = Loadouts.configure(b, 1, :inventory_order, inventory)
    assert b.heroes[1].hero.inventory_order == inventory
    assert b.heroes[1].hero.skill_order == skills
    b = Loadouts.configure(b, 1, :sell, hd(inventory))
    assert b.heroes[1].hero.inventory_order == tl(inventory)
    assert b.heroes[1].hero.skill_order == skills
  end
end
