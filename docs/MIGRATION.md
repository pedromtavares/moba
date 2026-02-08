# MIGRATION.md — V1 → V1.5

## Overview

V1.5 transforms BrowserMOBA's training system into a self-contained roguelite experience where:

- **Training** is item-free, focused on skill choices and resource management
- **Items** are purchased post-training with shards for Arena use
- **Gold** exists only within training runs (consumables + buybacks)
- **Arena** is duels-only, rewards shards

---

## Philosophy

| V1 | V1.5 |
|----|------|
| Training = XP + Gold + Items | Training = Roguelite survival |
| Gold used for items during training | Gold used for consumables + buybacks |
| Items affect training balance | Items are PvP-only (post-training) |
| 5v5 and Duels | Duels only |
| Target selection from 6-9 options | Choose 1 of 3 hard targets |
| XP curve determines leveling | +1 level per battle (no XP math) |
| Brackets (Plebs/Shadows/Immortals) | Leagues (Bronze → Grandmaster) |
| Cross-bracket matchmaking | Same-league matchmaking only |

---

## Training System

### Turn Structure by Account Tier

| Account Tier | Turns | Max Level | Skill Points | Stat-Only Turns |
|--------------|-------|-----------|--------------|-----------------|
| Tier 0 (Initiate) | 15 | 15 | 15 | 0 |
| Tier 1 (Novice) | 20 | 20 | 18 | 2 |
| Tier 2+ (Adept+) | 25 | 25 | 18 | 7 |

**Design rationale:** New players reach Arena faster with shorter runs. Veterans can train stronger heroes with longer runs. This mirrors DotA 1 where late levels were pure stat growth after skills were maxed.

### Skill Point Distribution

```
Turns 1-18: +1 level, +1 skill point each
Turns 19+:  +1 level, no skill point (stats only)

Skill points needed to max:
- 3 normal skills × 5 levels = 15
- 1 ultimate × 3 levels = 3
- Total: 18 points
```

**Tier 0 (15 points):** Must make tradeoffs - can't max everything
**Tier 1+ (18 points):** Can max all skills by turn 18

### Turn Flow

```
Each Turn:
1. View 3 targets (all hard difficulty, level = yours or +1)
2. Pick a target based on avatar matchup
3. Buy pre-battle consumables with gold (optional)
4. Battle
   └── Can use in-battle consumables (more expensive)
5. Win:
   ├── +1 level
   ├── +1 skill point (turns 1-18 only)
   ├── +gold reward
   └── +interest on saved gold
6. Lose:
   ├── Pay buyback cost to continue, OR
   └── Run ends (hero finishes at current level)
7. Level a skill (turns 1-18 only)
8. Repeat until max turns or can't afford buyback
```

### Speed Mechanic

**V1:** Speed stat determines first-attack chance (80 speed = 80% chance)

**V1.5:** Speed fixed at 100 for all training battles. Player always attacks first.

This removes RNG from training, making it pure skill/resource management. Speed becomes a PvP-only stat.

---

## Auto-Battle & Checkpoints

Preserves the V1 feel of "obligatory battles + passive farming" in roguelite form.

### Structure

| Turn Type | Control | Frequency |
|-----------|---------|-----------|
| **Checkpoint** | Manual (required) | Every 5 turns |
| **Regular** | Manual OR Auto | All other turns |
| **Boss** | Manual (required) | Turn 25 only (Tier 2+) |

```
Turns 1-4:   Regular (can auto)
Turn 5:      CHECKPOINT (manual required)
Turns 6-9:   Regular (can auto)
Turn 10:     CHECKPOINT (manual required)
Turns 11-14: Regular (can auto)
Turn 15:     CHECKPOINT (manual required)
Turns 16-18: Regular (can auto, skill complete)
Turns 19-24: Regular (can auto, stat phase)
Turn 25:     BOSS - Roshan (manual required)
```

### Checkpoint Count by Tier

| Tier | Turns | Checkpoints | Auto-able | Manual Required |
|------|-------|-------------|-----------|-----------------|
| 0 | 15 | 3 | 12 | 3 |
| 1 | 20 | 4 | 16 | 4 |
| 2+ | 25 | 5 + Boss | 19 | 6 |

### Auto-Battle Flow

Player **still picks consumables**, fight resolves automatically:

```
Auto-Battle Turn:
1. View 3 targets
2. Pick a target
3. Buy consumables (pre-battle AND in-battle)
4. Choose: [Manual Battle] or [Auto-Battle]
5. If Auto: Fight resolves instantly with auto-triggers
6. Result: +1 level, +gold, etc.
```

### Consumable Auto-Triggers

In-battle consumables trigger automatically based on conditions:

| Consumable | Auto-Trigger Condition |
|------------|------------------------|
| Faerie Fire | HP drops below 40% |
| Mango | MP drops below 30% |
| Cheese | Would die from next hit |
| Refresher Shard | All skills on cooldown |
| Dust | Enemy has 3+ buffs |

**Strategic choice remains:** "Do I bring Cheese as insurance, or save gold and risk it?"

### Comparison to V1

| Aspect | V1 | V1.5 |
|--------|-----|------|
| Obligatory battles | ~20 (leagues) | 5-6 (checkpoints + boss) |
| Passive option | Meditation/Mining | Auto-battles |
| Player choice during passive | None | Pick consumables |
| Estimated time | 30-45 min | 15-25 min |

This preserves the hybrid active/passive feel while fitting the roguelite model.

---

## Training Economy

### Gold

Gold exists **only within the training run**. It has no value after training ends.

**Starting gold:** 200g

**Battle rewards (scaling by turn):**
```
Turns 1-10:  100g + (turn × 5)   → 105-150g
Turns 11-18: 150g + (turn × 5)   → 205-240g
Turns 19-25: 200g + (turn × 10)  → 390-450g
```

**Interest:** 10% of saved gold per turn (cap: +50g)

**Buyback cost:** `max(50, level × 10)`
```
Levels 1-10:  55-100g
Levels 11-18: 110-180g
Levels 19-25: 190-250g
```

### Resource Management Strategy

Gold serves as granular "lives":
- More gold = more chances to continue after death
- Spending on consumables = trading future buybacks for current power
- Interest = earning more survival margin over time

**Conservative play:** Save gold, use fewer consumables, rely on skill
**Aggressive play:** Spend on consumables, win harder fights, risk running out

---

## Consumables

### Pre-Battle (Cheaper)

Apply before battle starts. Strategic planning.

| Name | Cost | Effect |
|------|------|--------|
| Healing Salve | 80g | Restore 40% HP |
| Clarity | 60g | Restore 60% MP |
| TP Scroll | 150g | Full HP + MP restore |
| Blade | 100g | First attack deals +30% damage |
| Chainmail | 100g | +15 armor for this battle |
| Cloak | 100g | +20% magic resistance for this battle |
| Smoke | 120g | Enemy's first skill starts on cooldown |

### In-Battle (Emergency)

More expensive, but can save a run. Use during battle.

| Name | Cost | Effect |
|------|------|--------|
| Cheese | 300g | Survive next lethal hit with 1 HP |
| Faerie Fire | 150g | Instant +20% HP heal |
| Mango | 100g | Instant +30% MP restore |
| Refresher Shard | 250g | Reset all your cooldowns |
| Dust | 200g | Purge all enemy buffs |

### Design Note

No raw stat boost consumables (+HP, +ATK, etc.) for simplicity. Consumables solve tactical problems, not stat gaps. If balance requires stat consumables, add later.

---

## Target System

**V1:** 6-9 targets shown with visible difficulty labels (weak/moderate/strong)

**V1.5:**
- 3 targets shown per turn
- All "hard" difficulty internally (no label visible)
- Level = player level or +1
- Player picks based on **avatar matchup**, not difficulty
- New 3 targets generated after each battle

**Design rationale:** Removes "easy target hunting" strategy. Focus shifts to "How do I prepare for whatever comes?" while still giving meaningful choice via avatar matchup.

---

## Run Outcomes

| Outcome | Level | Skills | Arena Viability |
|---------|-------|--------|-----------------|
| Perfect (Tier 2+) | 25 | All maxed (18) | Fully competitive |
| Good | 20-24 | All maxed | Competitive, slight stat gap |
| Early exit | 15-19 | All/most maxed | Playable, noticeable gap |
| Failed | <15 | Partial | Weak, but still usable |

**Key design:** Even failed runs produce a usable Arena hero. The "punishment" for dying is a weaker hero, not wasted time. This prevents rage-quitting.

---

## Post-Training: Items

After training completes:
- Hero has level + skills, no items
- Use **shards** to buy items from shop
- Same item system as V1, different currency

### Shard Prices

```
Normal:    40 shards
Rare:      120 shards
Epic:      240 shards
Legendary: 480 shards

Full legendary build: 6 × 480 = 2,880 shards
```

### Shard Sources

| Source | Amount |
|--------|--------|
| Quest completion | 200-5,000 (existing) |
| Manual matchmaking | 20 per match (existing) |
| Arena duel win | 50 shards (new) |
| Arena duel participation | 10 shards (new) |

---

## Arena Changes

### Remove 5v5 Matches

5v5 auto-battles weren't engaging without player agency during fights. Duels are the competitive mode.

**Files to deprecate:**
- Match-related code in `arena.ex`
- `MatchLive` and related LiveViews
- Daily match limit logic

### Duels Only

- Keep all existing duel infrastructure
- Add shard rewards (50 win, 10 participation)
- Duels become primary Arena activity

---

## Arena League Progression

### New League System

Replaces current bracket system (Plebs/Shadows/Immortals) with a proper ranked ladder, similar to solo queue in MOBAs/RTS games.

**7 Leagues:**

| League | Tier |
|--------|------|
| Bronze | 0 |
| Silver | 1 |
| Gold | 2 |
| Platinum | 3 |
| Diamond | 4 |
| Master | 5 |
| Grandmaster | 6 |

### How It Works

**Matchmaking:**
- Players only match against others in their **same league**
- No cross-league matchmaking
- Creates fair fights and meaningful rank

**League Position:**
- Based on **season points** within your league
- Each league has minimum 5 players
- Position updates after each duel

**Promotion/Demotion:**
- If your SP exceeds the bottom player of the league above → you swap positions
- If someone below you exceeds your SP → you swap positions
- Creates dynamic, competitive ladder

```
Example:
- You're Diamond #1 with 450 SP
- Master #5 has 440 SP
- You win a duel, gain 15 SP → now 465 SP
- You surpass Master #5 → Promoted to Master, they demote to Diamond
```

### Hero Cooldown System

To prevent spamming the same hero, heroes have cooldown after Arena use.

**Mechanic:**
- After using a hero in a duel, it goes on cooldown
- Must rotate through roster to continue playing
- Encourages training multiple heroes
- Roster of 10 heroes recommended for continuous play

**Implementation:**
```elixir
# Hero schema
field :arena_cooldown_until, :utc_datetime
```

### Unlock Requirement

**Arena unlocks after 2 trained heroes.**

This ensures:
- Players experience training first
- Have at least 2 heroes to rotate
- Understand game mechanics before PvP

### Shard Rewards by League

Higher leagues = more shards per duel (rewards climbing).

| League | Win | Participation |
|--------|-----|---------------|
| Bronze | 30 | 5 |
| Silver | 35 | 6 |
| Gold | 40 | 7 |
| Platinum | 45 | 8 |
| Diamond | 50 | 10 |
| Master | 60 | 12 |
| Grandmaster | 75 | 15 |

---

## Migration Day: League Placement

**Current V1 brackets → V1.5 leagues:**

| V1 Bracket | V1.5 League |
|------------|-------------|
| Immortals (top 5) | Grandmaster |
| Shadows | Master |
| Plebs (top 20% by SP) | Diamond |
| Plebs (next 20%) | Platinum |
| Plebs (next 20%) | Gold |
| Plebs (next 20%) | Silver |
| Plebs (bottom 20%) | Bronze |

**Process:**
1. Take all current Immortals → place in Grandmaster
2. Take all current Shadows → place in Master
3. Sort remaining Plebs by season points
4. Distribute into Diamond → Bronze by percentile
5. Reset daily wins, keep season points as starting position

---

## What Gets Removed

| Feature | Status |
|---------|--------|
| XP system | Removed (level = turn number) |
| Gold for items in training | Removed |
| Item shop during training | Removed |
| Target difficulty labels | Removed (all hard internally) |
| Weak/Moderate targets | Removed |
| 6-9 target choices | Reduced to 3 |
| Meditation/Mining | Removed (no passive farming) |
| 5v5 Matches | Removed |
| PvE League step system | Simplified (just turn progression) |
| Bracket system (Plebs/Shadows/Immortals) | Replaced with ranked leagues |
| Cross-bracket matchmaking | Replaced with same-league only |
| Daily promotion/demotion | Replaced with dynamic SP-based swaps |

---

## What Stays

| Feature | Status |
|---------|--------|
| Avatars | Same |
| Skills | Same mechanics, now all maxable |
| Items | Same, moved to post-training |
| Battle engine | Same |
| Bot generation | Modified (no items, hard difficulty) |
| Shards | Expanded (now buys items too) |
| Account tiers | Same, affects turn count |
| Duels | Same, now primary PvP mode |
| Season points | Same, now determines league position |
| Duel mechanics | Same (pick/counterpick, 2 battles) |

---

## Comparison: V1 vs V1.5 Heroes

| Aspect | V1 Max Hero | V1.5 Max Hero |
|--------|-------------|---------------|
| Level | 25-28 | 25 |
| Skill points used | 14 (can't max all) | 18 (all maxed) |
| Items | 6 legendaries | 6 legendaries |
| Total farm ranking | Yes | No (different metric needed) |

**V1.5 heroes at level 25 are slightly stronger** than V1 heroes due to having all skills maxed (18 vs 14 points). This rewards completing the harder roguelite.

---

## Implementation Phases

### Phase 1: Roguelite Foundation
- Add consumable system (schema, module, UI)
- Add pre-battle and in-battle consumable logic
- Keep items enabled for testing
- **Estimate:** 3-4 days

### Phase 1b: Auto-Battle System
- Add auto-battle option for non-checkpoint turns
- Implement consumable auto-triggers
- Add checkpoint turn detection (turns 5, 10, 15, 20, 25)
- **Estimate:** 2-3 days

### Phase 2: Remove Items from Training
- Disable item shop during training
- Heroes start with no items
- Bots in training have no items
- Remove gold rewards, replace with consumable economy
- **Estimate:** 2-3 days

### Phase 3: Leveling Rework
- Remove XP curve, +1 level per battle
- Skill point every turn (turns 1-18)
- Stat-only levels (turns 19+)
- Adjust turn counts by tier (15/20/25)
- **Estimate:** 2-3 days

### Phase 4: Target System
- Reduce to 3 targets
- All hard difficulty
- Remove difficulty labels from UI
- **Estimate:** 1-2 days

### Phase 5: Post-Training Items
- Add "Equip" phase after training
- Items purchasable with shards
- Add shard prices to items
- **Estimate:** 2-3 days

### Phase 6: Arena Cleanup
- Hide/remove 5v5 matches
- Add shard rewards to duels
- **Estimate:** 1-2 days

### Phase 7: Arena League System
- Add league field to Player (0-6)
- Implement league-based matchmaking
- Add promotion/demotion logic
- Add hero cooldown system
- League-scaled shard rewards
- **Estimate:** 3-4 days

### Phase 8: Migration Day
- Map existing brackets to new leagues
- Distribute Plebs by SP percentile
- Reset daily stats, preserve SP as starting position
- **Estimate:** 1 day (migration script)

### Total Estimate: 19-27 days

---

## Database Migration

```elixir
defmodule Moba.Repo.Migrations.V15Roguelite do
  use Ecto.Migration

  def change do
    # Extend items for consumables and pricing
    alter table(:items) do
      add :consumable, :boolean, default: false
      add :gold_cost, :integer     # Explicit gold cost for training (overrides rarity-based)
      add :shard_cost, :integer    # For post-training shop
    end

    # Roguelite fields for heroes
    alter table(:heroes) do
      add :run_gold, :integer, default: 200
      add :current_hp, :integer           # Persists between training battles
      add :current_mp, :integer           # Persists between training battles
      add :arena_cooldown_until, :utc_datetime  # Hero cooldown for Arena
    end

    # League system for players
    alter table(:players) do
      add :arena_league, :integer, default: 0  # 0=Bronze, 6=Grandmaster
    end
  end
end
```

No new tables needed. Consumables are Items with `consumable: true`. Uses existing:
- Item effect system via `Spell.ex`
- `gold_cost` for training prices (explicit), falls back to rarity-based `item_price/1`
- `shard_cost` for post-training shop (explicit), falls back to rarity-based default
- Item inventory system

### Migration Day Script

```elixir
defmodule Moba.Repo.Migrations.V15LeaguePlacement do
  use Ecto.Migration
  import Ecto.Query

  @leagues %{
    grandmaster: 6,
    master: 5,
    diamond: 4,
    platinum: 3,
    gold: 2,
    silver: 1,
    bronze: 0
  }

  def up do
    # Immortals (pvp_tier 2) → Grandmaster
    from(p in "players", where: p.pvp_tier == 2)
    |> Moba.Repo.update_all(set: [arena_league: @leagues.grandmaster])

    # Shadows (pvp_tier 1) → Master
    from(p in "players", where: p.pvp_tier == 1)
    |> Moba.Repo.update_all(set: [arena_league: @leagues.master])

    # Plebs (pvp_tier 0) → Distribute by SP percentile
    plebs = from(p in "players", where: p.pvp_tier == 0, order_by: [desc: p.pvp_points])
            |> Moba.Repo.all()
    
    total = length(plebs)
    
    plebs
    |> Enum.with_index()
    |> Enum.each(fn {player, index} ->
      percentile = index / total
      league = cond do
        percentile < 0.20 -> @leagues.diamond
        percentile < 0.40 -> @leagues.platinum
        percentile < 0.60 -> @leagues.gold
        percentile < 0.80 -> @leagues.silver
        true -> @leagues.bronze
      end
      
      from(p in "players", where: p.id == ^player.id)
      |> Moba.Repo.update_all(set: [arena_league: league])
    end)
  end
end
```

---

## Resolved Questions

1. **Training ranking:** Final level reached + completion time (tiebreaker)

2. **Roshan/Boss:** Yes, keep same logic. Roshan is the final boss at turn 25 for Tier 2+ players.

3. **Multiple runs:** Yes, players can train multiple heroes per avatar (different skill builds). Best hero per avatar tracked in collection.

4. **Existing heroes:** No changes needed - they're already equipped. Players can use shards to change equipment if desired. Most veterans have plenty of shards.

5. **Bot items in Arena:** Yes, same as current. Arena bots have full item builds.

6. **Shard buyback:** Keep the shard buyback option from V1. Players who have grinded shards deserve to not waste time on failed runs. Avoids frustration for invested players.

---

## Edge Cases & Systems to Address

### Roshan/Boss by Tier

| Tier | Turns | Has Roshan? | Notes |
|------|-------|-------------|-------|
| Tier 0 | 15 | No | Too short, no boss |
| Tier 1 | 20 | No | No boss, just complete 20 turns |
| Tier 2+ | 25 | Yes | Roshan at turn 25 (final challenge) |

Roshan remains the "true ending" for veteran players. New players don't face him.

### HP/MP Persistence (Roguelite)

**V1:** HP/MP reset to full between battles.

**V1.5:** HP/MP persist between battles (roguelite style).

```elixir
# Hero schema - track current HP/MP during training
field :current_hp, :integer  # Persists between battles
field :current_mp, :integer  # Persists between battles
```

This is what makes consumables valuable - you need healing between fights.

### Shard Buyback Details

Keep V1 shard buyback with same rules:
- Cost: 5% of current shards (minimum 5 shards)
- Available when: Account tier > 3, hero not at Master league yet
- Benefit: Preserves run (no gold penalty), avoids frustration

### PvE Tiers (Account Progression)

Current requirements reference "Platinum+ league" which is PvE leagues. Update to reference **level reached**:

| Tier | Old Requirement | New Requirement |
|------|-----------------|-----------------|
| 0 → 1 | 2 avatars at Platinum+ | 2 avatars trained to level 15+ |
| 1 → 2 | 5 avatars at Platinum+ | 5 avatars trained to level 15+ |
| 2 → 3 | 10 avatars at Platinum+ | 10 avatars trained to level 15+ |
| 3 → 4 | 15 avatars at Platinum+ | 15 avatars trained to level 15+ |
| 4 → 5 | 20 avatars at Master+ | 20 avatars trained to level 20+ |
| 5 → 6 | 20 avatars at GM | 20 avatars trained to level 25 |
| 6 → 7 | 20 avatars at GM + 60K | 20 avatars at level 25 + perfect run |

### Quests

Keep quests, update rewards to reference new system:
- Tier advancement shards stay same
- Quest tracking changes from "league_tier" to "level"

### Hero Collection Tracking

**V1:** Best hero per avatar by `total_gold_farm + total_xp_farm`

**V1.5:** Best hero per avatar by `level` (primary), then `finished_at` (tiebreaker for same level)

### Training State Machine

**V1 states:** `alive`, `dead`, `meditating`, `mining`

**V1.5 states:** `alive`, `dead` only

Remove meditation/mining logic from:
- `lib/moba/game/heroes.ex` - `finish_farming!/1`, `start_farming!/3`
- `lib/moba/game/training.ex` - farming-related functions
- `lib/moba_web/live/training_live.ex` - farming UI

### Deprecated Hero Fields

```elixir
# Fields to deprecate/remove from Hero schema
field :pve_farming_turns, :integer          # Remove
field :pve_farming_started_at, :utc_datetime # Remove
embeds_many :pve_farming_rewards, ...        # Remove
field :total_gold_farm, :integer             # Keep for legacy, not used for new heroes
field :total_xp_farm, :integer               # Keep for legacy, not used for new heroes
```

### Teams

**V1:** Team management for 5v5 matches.

**V1.5:** Remove teams entirely OR repurpose for future features.

Recommendation: Keep schema but hide UI. May be useful later if we add team modes.

### Tavern (Unlock Shop)

Stays the same:
- Avatar unlocks: 150 shards
- Skill unlocks: 100 shards
- Skin unlocks: 500/1000 shards

No changes needed.

### Starter Builds

**V1:** Starter builds include skill recommendations + item builds.

**V1.5:** Starter builds only need skill recommendations (items not used in training).

Update `lib/moba/game/builds.ex` to skip item suggestions for new heroes.

### Immortal Streak Replacement

**V1:** Consecutive days as #1 in Immortals bracket, gives stat penalty + season score bonus.

**V1.5 Options:**
1. **Keep similar:** Consecutive days as #1 in Grandmaster
2. **Remove:** Simplify to just league position
3. **Modify:** Streak of wins without losses in Grandmaster

Recommendation: Option 1 - keep it, just reference Grandmaster instead of Immortals.

### Season Reset

**V1:** Resets daily wins, recalculates brackets.

**V1.5:** 
- Reset all players to starting league based on previous season rank
- Top 50% of each league stays, bottom 50% drops one league
- Or: Everyone drops 1 league (GM → Master, Master → Diamond, etc.)
- Bronze players stay Bronze

### Auto-Matchmaking (Conductor)

**V1:** `Conductor.season_tick!/0` creates auto 5v5 matches every 30 min.

**V1.5:** Remove auto-match logic. Duels are player-initiated only.

Alternative: Add auto-duels for inactive players? (Probably not - duels require picks)

### Daily/Season Rankings

**V1:** 
- Daily: by `daily_wins`
- Season: by `(100 × immortal_streak) + (100 × pve_tier) + pvp_points`

**V1.5:**
- Daily: by `daily_wins` within league
- Season: by `arena_league` (primary) + `pvp_points` (secondary)

Top of Grandmaster = #1 overall.

---

## Summary

V1.5 creates cleaner separation:

```
Training (Roguelite)          Arena (PvP)
├── No items                  ├── Items (bought with shards)
├── Gold for survival         ├── Shards as currency
├── Skill expression          ├── Build expression  
├── Solo challenge            ├── Ranked leagues (Bronze → GM)
├── Level 15-25 heroes        ├── Same-league matchmaking
└── 15-25 turns by tier       └── Hero cooldown rotation
```

**Progression flow:**
```
New Player
    │
    ▼
Train 2 heroes (15 turns each, ~30 min total)
    │
    ▼
Unlock Arena → Start in Bronze
    │
    ▼
Win duels → Earn shards → Buy items → Climb leagues
    │
    ▼
Rank up account → Longer training (20-25 turns) → Stronger heroes
    │
    ▼
Reach Grandmaster
```

New players get to Arena fast (15 turns). Veterans train stronger heroes (25 turns). The roguelite is self-contained. Arena has meaningful ranked progression with same-league matchmaking.
