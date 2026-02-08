# PHASES.md — V1.5 Implementation Details

Detailed implementation steps for each phase of the V1 → V1.5 migration.

---

## Phase 1: Roguelite Foundation (3-4 days)

### Goal
Add consumable system by extending existing Item schema. No new tables needed.

### Schema Changes

**1. Extend Item schema**

```elixir
# Migration
alter table(:items) do
  add :consumable, :boolean, default: false
  add :gold_cost, :integer     # Explicit gold cost (training), overrides rarity-based price
  add :shard_cost, :integer    # For post-training shop
end
```

**2. Update Item schema**

```elixir
# lib/moba/game/schema/item.ex - add fields
field :consumable, :boolean, default: false
field :gold_cost, :integer      # Explicit gold cost for training
field :shard_cost, :integer     # Shard cost for post-training shop
```

**3. Add Hero roguelite fields**

```elixir
# Migration
alter table(:heroes) do
  add :run_gold, :integer, default: 200
  add :current_hp, :integer           # Persists between training battles
  add :current_mp, :integer           # Persists between training battles
end
```

**4. Update Hero schema**

```elixir
# lib/moba/game/schema/hero.ex - add fields
field :run_gold, :integer, default: 200
field :current_hp, :integer    # Roguelite HP persistence
field :current_mp, :integer    # Roguelite MP persistence
```

### Seed Consumable Items

Consumables are Items with `consumable: true` and explicit `gold_cost`.

```elixir
# priv/repo/seeds/consumables.exs

consumables = [
  # Pre-battle consumables (use between battles)
  %{
    code: "healing_salve",
    name: "Healing Salve", 
    rarity: "normal",
    consumable: true,
    gold_cost: 80,
    active: true,
    description: "Restore 40% HP before battle",
    hp_regen_multiplier: 0.4
  },
  %{
    code: "clarity",
    name: "Clarity",
    rarity: "normal",
    consumable: true,
    gold_cost: 60,
    active: true,
    description: "Restore 60% MP before battle",
    mp_regen_multiplier: 0.6
  },
  %{
    code: "tp_scroll",
    name: "TP Scroll",
    rarity: "rare",
    consumable: true,
    gold_cost: 150,
    active: true,
    description: "Full HP and MP restore",
    hp_regen_multiplier: 1.0,
    mp_regen_multiplier: 1.0
  },
  %{
    code: "smoke_of_deceit",
    name: "Smoke of Deceit",
    rarity: "normal",
    consumable: true,
    gold_cost: 120,
    active: true,
    description: "Enemy's first skill starts on cooldown",
    extra_amount: 1
  },
  %{
    code: "blade_of_attack",
    name: "Blade of Attack",
    rarity: "normal",
    consumable: true,
    gold_cost: 100,
    active: true,
    description: "First attack deals +30% damage",
    atk_multiplier: 0.3
  },
  %{
    code: "chainmail",
    name: "Chainmail",
    rarity: "normal",
    consumable: true,
    gold_cost: 100,
    active: true,
    description: "+15 armor for this battle",
    armor_amount: 15
  },
  
  # In-battle consumables (emergency, more expensive)
  %{
    code: "cheese",
    name: "Cheese",
    rarity: "rare",
    consumable: true,
    gold_cost: 300,
    active: true,
    description: "Survive next lethal hit with 1 HP"
  },
  %{
    code: "enchanted_mango",
    name: "Enchanted Mango",
    rarity: "normal",
    consumable: true,
    gold_cost: 100,
    active: true,
    description: "Instant +30% MP restore",
    mp_regen_multiplier: 0.3
  },
  %{
    code: "faerie_fire",
    name: "Faerie Fire",
    rarity: "normal",
    consumable: true,
    gold_cost: 150,
    active: true,
    description: "Instant +20% HP heal",
    hp_regen_multiplier: 0.2
  },
  %{
    code: "refresher_shard",
    name: "Refresher Shard",
    rarity: "epic",
    consumable: true,
    gold_cost: 250,
    active: true,
    description: "Reset all your cooldowns"
  },
  %{
    code: "dust_of_appearance",
    name: "Dust of Appearance",
    rarity: "rare",
    consumable: true,
    gold_cost: 200,
    active: true,
    description: "Purge all enemy buffs"
  }
]
```

### Add Effects to Spell.ex

```elixir
# lib/moba/engine/core/spell.ex - add consumable effects

# Pre-battle healing (applied before battle starts)
defp effects_for(%{resource: %Item{code: "healing_salve"}} = turn, _options) do
  turn
  |> Effect.hp_regen_by_total()
end

defp effects_for(%{resource: %Item{code: "clarity"}} = turn, _options) do
  turn
  |> Effect.mp_regen_by_total()
end

defp effects_for(%{resource: %Item{code: "tp_scroll"}} = turn, _options) do
  turn
  |> Effect.full_hp_restore()
  |> Effect.full_mp_restore()
end

defp effects_for(%{resource: %Item{code: "smoke_of_deceit"}} = turn, _options) do
  turn
  |> Effect.enemy_skill_cooldown()
end

# In-battle consumables
defp effects_for(%{resource: %Item{code: "cheese"}} = turn, _options) do
  turn
  |> Effect.survive_lethal()
end

defp effects_for(%{resource: %Item{code: "enchanted_mango"}} = turn, _options) do
  turn
  |> Effect.instant_mp_restore()
end

defp effects_for(%{resource: %Item{code: "faerie_fire"}} = turn, _options) do
  turn
  |> Effect.instant_hp_restore()
end

defp effects_for(%{resource: %Item{code: "refresher_shard"}} = turn, _options) do
  turn
  |> Effect.reset_all_cooldowns()
end

defp effects_for(%{resource: %Item{code: "dust_of_appearance"}} = turn, _options) do
  turn
  |> Effect.purge_defender_buffs()
end
```

### Add Query Helpers

```elixir
# lib/moba/game/query/item_query.ex
def consumables(query) do
  from i in query, where: i.consumable == true
end

def non_consumables(query) do
  from i in query, where: i.consumable == false or is_nil(i.consumable)
end
```

### Update Items Module

```elixir
# lib/moba/game/items.ex

def list_consumables do
  ItemQuery.base_current()
  |> ItemQuery.consumables()
  |> Repo.all()
end

def list_pre_battle_consumables do
  list_consumables()
  |> Enum.filter(&pre_battle?/1)
end

def list_in_battle_consumables do
  list_consumables()
  |> Enum.filter(&in_battle?/1)
end

# Consumables that can be used before battle (healing, buffs)
defp pre_battle?(item) do
  item.code in ["healing_salve", "clarity", "tp_scroll", "smoke_of_deceit", "blade_of_attack", "chainmail"]
end

# Consumables that can be used during battle (emergency)
defp in_battle?(item) do
  item.code in ["cheese", "enchanted_mango", "faerie_fire", "refresher_shard", "dust_of_appearance"]
end

# Gold cost for training (explicit gold_cost, or fallback to rarity-based)
def gold_cost(item) do
  item.gold_cost || item_price(item)
end

def buy_consumable!(hero, item) do
  price = gold_cost(item)
  
  if hero.run_gold >= price do
    # Add to hero's items temporarily, will be removed after use
    updated_hero = equip(hero, item)
    Game.update_hero!(updated_hero, %{run_gold: hero.run_gold - price})
  else
    {:error, :cannot_afford}
  end
end

# Remove consumable after use
def consume_item!(hero, item) do
  unequip(hero, [item])
end

# Shard cost for post-training shop (explicit shard_cost, or fallback to rarity-based)
def shard_cost(item) do
  item.shard_cost || default_shard_cost(item)
end

defp default_shard_cost(item) do
  case item.rarity do
    "normal" -> 40
    "rare" -> 120
    "epic" -> 240
    "legendary" -> 480
    _ -> 0
  end
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/game/schema/item.ex` | Add `consumable`, `shard_cost` fields |
| `lib/moba/game/schema/hero.ex` | Add `run_gold` field |
| `lib/moba/game/query/item_query.ex` | Add `consumables/1`, `non_consumables/1` |
| `lib/moba/game/items.ex` | Add consumable functions, `shard_cost/1` |
| `lib/moba/engine/core/spell.ex` | Add consumable effects |
| `lib/moba/engine/core/effect.ex` | Add new effect functions if needed |
| `lib/moba_web/live/training_live.ex` | Add consumable shop UI |

### Testing

```elixir
# test/moba/game/items_test.exs
describe "consumables" do
  test "list_consumables returns only consumable items" do
    consumables = Items.list_consumables()
    assert Enum.all?(consumables, & &1.consumable)
  end

  test "gold_cost returns explicit or rarity-based fallback" do
    item_explicit = %Item{rarity: "normal", gold_cost: 80}
    assert Items.gold_cost(item_explicit) == 80
    
    item_fallback = %Item{rarity: "normal", gold_cost: nil}
    assert Items.gold_cost(item_fallback) == 400  # normal rarity price
  end

  test "buy_consumable! deducts run_gold using gold_cost" do
    hero = insert(:hero, run_gold: 500)
    salve = Items.get_item_by_code!("healing_salve")  # gold_cost: 80
    
    {:ok, updated} = Items.buy_consumable!(hero, salve)
    assert updated.run_gold == 500 - 80
  end

  test "shard_cost returns explicit or default" do
    item = %Item{rarity: "legendary", shard_cost: nil}
    assert Items.shard_cost(item) == 480
    
    item_explicit = %Item{rarity: "legendary", shard_cost: 500}
    assert Items.shard_cost(item_explicit) == 500
  end
end
```

### Deliverable
- Consumables are Items with `consumable: true`
- Effects defined in existing Spell.ex pattern
- Hero has `run_gold` for training economy
- Items have `shard_cost` for post-training shop
- No new tables, uses existing architecture

---

## Phase 1b: Auto-Battle System (2-3 days)

### Goal
Add auto-battle option for non-checkpoint turns with consumable auto-triggers.

### Schema Changes

```elixir
# Hero schema - track turn state
field :current_turn, :integer, default: 1
```

### Constants

```elixir
# lib/moba/constants.ex

# Checkpoint turns (manual required)
@checkpoint_turns [5, 10, 15, 20, 25]

def checkpoint_turn?(turn), do: turn in @checkpoint_turns
def boss_turn?(turn, tier), do: turn == 25 && tier >= 2
```

### Auto-Battle Module

```elixir
# lib/moba/game/auto_battle.ex
defmodule Moba.Game.AutoBattle do
  @moduledoc """
  Handles automatic battle resolution with consumable triggers.
  """

  alias Moba.{Engine, Game}

  @consumable_triggers %{
    "faerie_fire" => {:hp_below, 0.4},
    "enchanted_mango" => {:mp_below, 0.3},
    "cheese" => {:would_die, true},
    "refresher_shard" => {:all_cooldowns, true},
    "dust_of_appearance" => {:enemy_buffs_gte, 3}
  }

  def resolve!(hero, target, consumables) do
    # Pre-battle consumables applied immediately
    hero = apply_pre_battle_consumables(hero, consumables)
    
    # Run battle with auto-trigger hooks
    battle = Engine.create_pve_battle!(%{attacker: hero, defender: target})
    
    # Process turns with auto-triggers
    battle = process_with_triggers(battle, consumables)
    
    battle
  end

  defp apply_pre_battle_consumables(hero, consumables) do
    pre_battle = Enum.filter(consumables, &pre_battle?/1)
    Enum.reduce(pre_battle, hero, &apply_consumable/2)
  end

  defp pre_battle?(item) do
    item.code in ["healing_salve", "clarity", "tp_scroll", "smoke_of_deceit", 
                  "blade_of_attack", "chainmail"]
  end

  defp process_with_triggers(battle, consumables) do
    in_battle = Enum.filter(consumables, &in_battle?/1)
    
    # Hook into turn processing to check triggers
    Enum.reduce_while(1..100, battle, fn _turn, battle ->
      if battle_over?(battle) do
        {:halt, battle}
      else
        battle = maybe_trigger_consumables(battle, in_battle)
        battle = Engine.process_turn(battle)
        {:cont, battle}
      end
    end)
  end

  defp maybe_trigger_consumables(battle, consumables) do
    attacker = battle.attacker
    
    Enum.reduce(consumables, battle, fn item, battle ->
      if should_trigger?(attacker, item) && has_consumable?(attacker, item) do
        trigger_consumable(battle, item)
      else
        battle
      end
    end)
  end

  defp should_trigger?(attacker, %{code: code}) do
    case @consumable_triggers[code] do
      {:hp_below, threshold} -> 
        attacker.current_hp / attacker.total_hp < threshold
      {:mp_below, threshold} -> 
        attacker.current_mp / attacker.total_mp < threshold
      {:would_die, true} -> 
        attacker.current_hp <= estimate_incoming_damage(attacker)
      {:all_cooldowns, true} -> 
        all_skills_on_cooldown?(attacker)
      {:enemy_buffs_gte, count} -> 
        length(attacker.defender_buffs || []) >= count
      _ -> false
    end
  end

  defp in_battle?(item) do
    item.code in ["cheese", "enchanted_mango", "faerie_fire", 
                  "refresher_shard", "dust_of_appearance"]
  end
end
```

### Training Module Updates

```elixir
# lib/moba/game/training.ex

def start_battle!(hero, target, mode, consumables \\ []) do
  case mode do
    :manual -> 
      start_manual_battle!(hero, target, consumables)
    :auto -> 
      start_auto_battle!(hero, target, consumables)
  end
end

def start_auto_battle!(hero, target, consumables) do
  # Deduct consumable costs
  hero = deduct_consumable_costs(hero, consumables)
  
  # Resolve battle automatically
  AutoBattle.resolve!(hero, target, consumables)
end

def checkpoint_turn?(hero) do
  Moba.checkpoint_turn?(hero.current_turn)
end

def can_auto_battle?(hero) do
  !checkpoint_turn?(hero) && !boss_turn?(hero)
end

defp boss_turn?(hero) do
  hero.current_turn == 25 && hero.pve_tier >= 2
end
```

### UI Changes

```elixir
# lib/moba_web/live/training_live.ex

def render(assigns) do
  ~H"""
  <div class="battle-options">
    <%= if @can_auto_battle do %>
      <button phx-click="manual_battle" phx-value-target={@selected_target}>
        Manual Battle
      </button>
      <button phx-click="auto_battle" phx-value-target={@selected_target}>
        Auto Battle
      </button>
    <% else %>
      <div class="checkpoint-notice">
        Checkpoint Battle - Manual Required
      </div>
      <button phx-click="manual_battle" phx-value-target={@selected_target}>
        Battle
      </button>
    <% end %>
  </div>
  """
end

def handle_event("auto_battle", %{"target" => target_id}, socket) do
  hero = socket.assigns.hero
  target = Targets.get_target!(target_id)
  consumables = socket.assigns.selected_consumables
  
  battle = Training.start_battle!(hero, target, :auto, consumables)
  
  {:noreply, assign(socket, battle: battle)}
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/constants.ex` | Add checkpoint turn logic |
| `lib/moba/game/auto_battle.ex` | New module for auto-resolution |
| `lib/moba/game/training.ex` | Add auto-battle support |
| `lib/moba_web/live/training_live.ex` | Add auto-battle UI option |

### Testing

```elixir
describe "auto_battle" do
  test "triggers faerie_fire when HP below 40%" do
    hero = %{current_hp: 300, total_hp: 1000}
    consumables = [Items.get_item_by_code!("faerie_fire")]
    
    assert AutoBattle.should_trigger?(hero, hd(consumables))
  end

  test "checkpoint turns require manual battle" do
    hero = %{current_turn: 5}
    refute Training.can_auto_battle?(hero)
    
    hero = %{current_turn: 6}
    assert Training.can_auto_battle?(hero)
  end
end
```

### Deliverable
- Auto-battle option on non-checkpoint turns
- Consumables auto-trigger based on conditions
- Checkpoints (turns 5, 10, 15, 20, 25) require manual play
- Boss (turn 25, Tier 2+) always manual

---

## Phase 2: Remove Items from Training (2-3 days)

### Goal
Disable item purchasing during training. Heroes train without items.

### Changes

**1. Modify hero creation**

```elixir
# lib/moba/game/heroes.ex
def create!(attrs, player, avatar, skills, items \\ []) do
  # For training heroes, always start with no items
  items = if training_hero?(attrs), do: [], else: items
  # ... rest of creation
end

defp training_hero?(attrs) do
  # Training heroes have pve_total_turns set
  Map.has_key?(attrs, :pve_total_turns) || Map.has_key?(attrs, "pve_total_turns")
end
```

**2. Disable shop in training**

```elixir
# lib/moba/game/items.ex
def can_buy_item?(hero, item) do
  # Disable during training
  if training?(hero) do
    false
  else
    hero = Repo.preload(hero, :items)
    !full_inventory?(hero) && can_equip_item?(hero, item) && hero.gold >= item_price(item)
  end
end

defp training?(hero), do: is_nil(hero.finished_at)
```

**3. Update bot generation for training**

```elixir
# lib/moba/game/heroes.ex
def create_bot!(avatar, level, difficulty, league_tier) do
  # Training bots have no items
  training_bot? = difficulty in ["weak", "moderate", "strong"]
  
  # ... existing code ...
  
  items = if training_bot?, do: [], else: Enum.uniq_by(build.items, & &1.id)
  
  # ... rest of creation
end
```

**4. Hide item shop in training UI**

```elixir
# lib/moba_web/live/training_live.ex
def render(assigns) do
  ~H"""
  <!-- Remove or hide item shop section -->
  <!-- Replace with consumable shop from Phase 1 -->
  """
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/game/heroes.ex` | Create without items for training |
| `lib/moba/game/items.ex` | Block purchases during training |
| `lib/moba_web/live/training_live.ex` | Remove item shop UI |
| `lib/moba_web/live/training_live/shop.ex` | Replace with consumable shop |

### Testing

- Create a training hero → verify no items
- Try to buy item during training → verify blocked
- Training bot → verify no items
- Arena bot → verify still has items

---

## Phase 3: Leveling Rework (2-3 days)

### Goal
Remove XP curve, implement +1 level per battle, skill points turns 1-18 only.

### Changes

**1. Update constants**

```elixir
# lib/moba/constants.ex

# New: fixed turns by tier
def total_pve_turns(0), do: 15  # Tier 0: Initiate
def total_pve_turns(1), do: 20  # Tier 1: Novice  
def total_pve_turns(_), do: 25  # Tier 2+: Adept and above

# New: skill point cap
@skill_point_cap 18

def skill_point_cap, do: @skill_point_cap
```

**2. Simplify leveling**

```elixir
# lib/moba/game/schema/hero.ex

# Remove XP-based leveling, replace with direct level increment
def level_up_from_battle(hero) do
  next_level = hero.level + 1
  
  # Skill points only for levels 1-18
  skill_levels = if next_level <= 18 do
    hero.skill_levels_available + 1
  else
    hero.skill_levels_available
  end
  
  avatar = hero.avatar
  
  %{
    level: next_level,
    skill_levels_available: skill_levels,
    atk: hero.atk + avatar.atk_per_level,
    total_hp: hero.total_hp + avatar.hp_per_level,
    total_mp: hero.total_mp + avatar.mp_per_level
  }
end
```

**3. Update battle finalization**

```elixir
# lib/moba/game/training.ex

def finalize_pve_attacker!(attacker, defender, winner, rewards) do
  win = winner && winner.id == attacker.id
  
  updates = if win do
    # Level up directly (no XP)
    level_updates = Hero.level_up_from_battle(attacker)
    
    # Gold reward for consumable economy
    gold_reward = battle_gold_reward(attacker.level)
    
    Map.merge(level_updates, %{
      wins: attacker.wins + 1,
      run_gold: attacker.run_gold + gold_reward
    })
  else
    %{losses: attacker.losses + 1, pve_state: "dead"}
  end
  
  # Apply interest on saved gold after battle
  updates = if win do
    interest = min(50, trunc(attacker.run_gold * 0.10))
    Map.put(updates, :run_gold, updates.run_gold + interest)
  else
    updates
  end
  
  update_attacker!(attacker, updates)
  |> maybe_finish_pve()
end

defp battle_gold_reward(level) when level <= 10, do: 100 + level * 5
defp battle_gold_reward(level) when level <= 18, do: 150 + level * 5
defp battle_gold_reward(level), do: 200 + level * 10
```

**4. Remove XP from UI**

Update all training UIs to show level progress (turn X of Y) instead of XP bar.

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/constants.ex` | Fixed turns, skill cap |
| `lib/moba/game/schema/hero.ex` | New `level_up_from_battle/1` |
| `lib/moba/game/training.ex` | Direct leveling, gold rewards |
| `lib/moba/game/heroes.ex` | Remove XP functions or deprecate |
| `lib/moba_web/views/training_view.ex` | Update progress display |
| `lib/moba_web/templates/training/*` | Remove XP bar, show turn progress |

### Testing

- Win battle at level 5 → verify level 6, +1 skill point
- Win battle at level 20 → verify level 21, no skill point
- Verify stat gains match avatar per-level values
- Verify gold reward scaling

---

## Phase 4: Target System (1-2 days)

### Goal
Reduce to 3 targets, all hard difficulty, no labels.

### Changes

**1. Update target generation**

```elixir
# lib/moba/game/targets.ex

def generate!(hero, codes) do
  # Clear existing targets
  delete_targets_for(hero)
  
  # Generate exactly 3 hard targets
  level = hero.level + 1  # Slightly above player level
  
  avatars = random_avatars(3, hero.avatar_id)
  
  Enum.each(avatars, fn avatar ->
    bot = Heroes.create_bot!(avatar, level, "strong", hero.league_tier)
    create_target!(hero, bot)
  end)
  
  hero
end

defp random_avatars(count, exclude_avatar_id) do
  Avatars.list_all()
  |> Enum.filter(&(&1.id != exclude_avatar_id))
  |> Enum.shuffle()
  |> Enum.take(count)
end
```

**2. Remove difficulty labels from UI**

```elixir
# lib/moba_web/templates/training/targets.html.heex

# Remove difficulty badges/labels
# Show only avatar info for matchup decisions
```

**3. Update target display**

Show avatar, level, and skills - but not "weak/moderate/strong" label.

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/game/targets.ex` | Generate 3 hard targets |
| `lib/moba_web/templates/training/targets.html.heex` | Remove difficulty labels |
| `lib/moba_web/views/training_view.ex` | Update target display helpers |

---

## Phase 5: Post-Training Items (2-3 days)

### Goal
Add equip phase after training, items bought with shards.

### Changes

**1. Add shard prices to items**

```elixir
# Migration
alter table(:items) do
  add :shard_price, :integer
end

# Seed shard prices
# Normal: 40, Rare: 120, Epic: 240, Legendary: 480
```

**2. Create post-training shop**

```elixir
# lib/moba/game/items.ex

def shard_price(item) do
  case item.rarity do
    "normal" -> 40
    "rare" -> 120
    "epic" -> 240
    "legendary" -> 480
    _ -> 0
  end
end

def buy_with_shards!(hero, item, user) do
  price = shard_price(item)
  
  if user.shard_count >= price && can_equip_item?(hero, item) do
    Accounts.update_user!(user, %{shard_count: user.shard_count - price})
    equip(hero, item)
  else
    {:error, :cannot_afford}
  end
end
```

**3. Create equip UI for finished heroes**

```elixir
# lib/moba_web/live/hero_live/equip.ex
defmodule MobaWeb.HeroLive.Equip do
  use MobaWeb, :live_view
  
  # Show available items
  # Show shard prices
  # Allow purchase and equip
end
```

**4. Update hero finishing flow**

After training completes, redirect to equip phase or show equip option.

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/game/items.ex` | `shard_price/1`, `buy_with_shards!/3` |
| `lib/moba/game/schema/item.ex` | Add `shard_price` field |
| `lib/moba_web/live/hero_live/equip.ex` | New LiveView for post-training equip |
| `lib/moba_web/router.ex` | Add route for equip page |

---

## Phase 6: Arena Cleanup (1-2 days)

### Goal
Remove 5v5, add shard rewards to duels.

### Changes

**1. Remove 5v5 match code**

```elixir
# lib/moba/game/arena.ex
# Deprecate or remove:
# - create_match!/2
# - auto_matchmaking!/0
# - match-related functions

# Keep all duel functions
```

**2. Add duel shard rewards**

```elixir
# lib/moba/game/duels.ex

def finalize_duel!(duel, winner_id) do
  # ... existing logic ...
  
  # Add shard rewards
  winner_player = Players.get_player!(winner_id)
  loser_player = Players.get_player!(loser_id)
  
  winner_shards = duel_win_shards(winner_player.arena_league)
  loser_shards = duel_participation_shards(loser_player.arena_league)
  
  Accounts.add_shards!(winner_player.user, winner_shards)
  Accounts.add_shards!(loser_player.user, loser_shards)
  
  # ... rest of finalization
end

defp duel_win_shards(league) do
  case league do
    0 -> 30  # Bronze
    1 -> 35  # Silver
    2 -> 40  # Gold
    3 -> 45  # Platinum
    4 -> 50  # Diamond
    5 -> 60  # Master
    6 -> 75  # Grandmaster
  end
end

defp duel_participation_shards(league) do
  case league do
    0 -> 5
    1 -> 6
    2 -> 7
    3 -> 8
    4 -> 10
    5 -> 12
    6 -> 15
  end
end
```

**3. Remove 5v5 from UI**

- Remove match-related navigation
- Remove match LiveViews
- Update Arena to show duels only

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/game/arena.ex` | Remove match functions |
| `lib/moba/game/duels.ex` | Add shard rewards |
| `lib/moba/conductor.ex` | Remove auto matchmaking |
| `lib/moba_web/live/arena_live/*` | Remove match UIs |
| `lib/moba_web/router.ex` | Remove match routes |

---

## Phase 7: Arena League System (3-4 days)

### Goal
Implement Bronze → GM leagues with same-league matchmaking.

### Changes

**1. Add league field to players**

```elixir
# Migration
alter table(:players) do
  add :arena_league, :integer, default: 0
end

# Add hero cooldown
alter table(:heroes) do
  add :arena_cooldown_until, :utc_datetime
end
```

**2. Create league constants**

```elixir
# lib/moba/constants.ex

@arena_leagues %{
  0 => "Bronze",
  1 => "Silver", 
  2 => "Gold",
  3 => "Platinum",
  4 => "Diamond",
  5 => "Master",
  6 => "Grandmaster"
}

def arena_leagues, do: @arena_leagues
def arena_league_name(tier), do: @arena_leagues[tier]
```

**3. Update matchmaking**

```elixir
# lib/moba/game/players.ex

def matchmaking_opponent(player) do
  # Only match within same league
  PlayerQuery.base()
  |> PlayerQuery.with_arena_league(player.arena_league)
  |> PlayerQuery.exclude(player.id)
  |> PlayerQuery.order_by_pvp_points()
  |> Repo.all()
  |> Enum.random()
end
```

**4. Add promotion/demotion logic**

```elixir
# lib/moba/game/arena.ex

def check_promotion!(player) do
  current_league = player.arena_league
  
  if current_league < 6 do
    # Get bottom player of league above
    upper_league_bottom = get_league_bottom(current_league + 1)
    
    if upper_league_bottom && player.pvp_points > upper_league_bottom.pvp_points do
      # Swap positions
      promote_player!(player, current_league + 1)
      demote_player!(upper_league_bottom, current_league)
    end
  end
  
  player
end

defp get_league_bottom(league) do
  PlayerQuery.base()
  |> PlayerQuery.with_arena_league(league)
  |> PlayerQuery.order_by_pvp_points(:asc)
  |> PlayerQuery.limit_by(1)
  |> Repo.one()
end
```

**5. Add hero cooldown**

```elixir
# lib/moba/game/heroes.ex

@arena_cooldown_hours 2

def set_arena_cooldown!(hero) do
  cooldown_until = Timex.shift(Timex.now(), hours: @arena_cooldown_hours)
  update!(hero, %{arena_cooldown_until: cooldown_until})
end

def on_arena_cooldown?(hero) do
  hero.arena_cooldown_until && 
    Timex.before?(Timex.now(), hero.arena_cooldown_until)
end

def available_arena_heroes(player) do
  trained_pvp_heroes(player.id)
  |> Enum.reject(&on_arena_cooldown?/1)
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/moba/constants.ex` | League definitions |
| `lib/moba/game/schema/player.ex` | Add `arena_league` |
| `lib/moba/game/schema/hero.ex` | Add `arena_cooldown_until` |
| `lib/moba/game/players.ex` | League-based matchmaking |
| `lib/moba/game/arena.ex` | Promotion/demotion logic |
| `lib/moba/game/heroes.ex` | Cooldown functions |
| `lib/moba_web/live/arena_live/*` | Show league, cooldowns |

---

## Phase 8: Migration Day (1 day)

### Goal
Execute migration script to place existing players into leagues.

### Migration Script

```elixir
# lib/mix/tasks/migrate_leagues.ex
defmodule Mix.Tasks.MigrateLeagues do
  use Mix.Task
  import Ecto.Query
  alias Moba.{Repo, Game}

  @leagues %{grandmaster: 6, master: 5, diamond: 4, platinum: 3, gold: 2, silver: 1, bronze: 0}

  def run(_) do
    Mix.Task.run("app.start")
    
    IO.puts("Starting league migration...")
    
    # Immortals → Grandmaster
    immortals = from(p in "players", where: p.pvp_tier == 2) |> Repo.all()
    IO.puts("Migrating #{length(immortals)} Immortals to Grandmaster")
    Enum.each(immortals, &update_league(&1, @leagues.grandmaster))
    
    # Shadows → Master
    shadows = from(p in "players", where: p.pvp_tier == 1) |> Repo.all()
    IO.puts("Migrating #{length(shadows)} Shadows to Master")
    Enum.each(shadows, &update_league(&1, @leagues.master))
    
    # Plebs → Distribute by percentile
    plebs = from(p in "players", where: p.pvp_tier == 0, order_by: [desc: p.pvp_points])
            |> Repo.all()
    
    total = length(plebs)
    IO.puts("Distributing #{total} Plebs across Bronze-Diamond")
    
    plebs
    |> Enum.with_index()
    |> Enum.each(fn {player, index} ->
      percentile = index / max(total, 1)
      league = cond do
        percentile < 0.20 -> @leagues.diamond
        percentile < 0.40 -> @leagues.platinum
        percentile < 0.60 -> @leagues.gold
        percentile < 0.80 -> @leagues.silver
        true -> @leagues.bronze
      end
      update_league(player, league)
    end)
    
    IO.puts("Migration complete!")
  end
  
  defp update_league(player, league) do
    from(p in "players", where: p.id == ^player.id)
    |> Repo.update_all(set: [arena_league: league])
  end
end
```

### Execution Checklist

1. [ ] Take database backup
2. [ ] Run schema migrations
3. [ ] Run `mix migrate_leagues`
4. [ ] Verify player distribution
5. [ ] Test matchmaking in each league
6. [ ] Monitor for issues
7. [ ] Announce to players

---

## Summary

| Phase | Days | Cumulative |
|-------|------|------------|
| Phase 1: Roguelite Foundation | 3-4 | 3-4 |
| Phase 1b: Auto-Battle System | 2-3 | 5-7 |
| Phase 2: Remove Items | 2-3 | 7-10 |
| Phase 3: Leveling Rework | 2-3 | 9-13 |
| Phase 4: Target System | 1-2 | 10-15 |
| Phase 5: Post-Training Items | 2-3 | 12-18 |
| Phase 6: Arena Cleanup | 1-2 | 13-20 |
| Phase 7: League System | 3-4 | 16-24 |
| Phase 8: Migration Day | 1 | 17-25 |

**Total: 17-25 days**

Each phase is independently deployable. Phases 1-4 can be feature-flagged for gradual rollout.
