# BrowserMOBA Product Doc


## Overview

BrowserMOBA is a free-to-play, open-source turn-based RPG that brings MOBA-style strategic gameplay to casual browser gaming. Players train heroes through PvE leagues, then compete in async PvP matches and real-time duels.

### Design Philosophy

- **Simple mechanics, deep strategy**: The game optimizes for straightforward rules with emergent complexity
- **Casual sessions**: 5-10 minute training runs, playable on any device with a browser
- **Async competition**: Players compete against historical opponents—past top players' heroes remain in the game forever
- **No pay-to-win**: All content unlockable through gameplay, no real-money purchases

### Core Game Loop

1. **Create Hero**: Choose avatar (20 available) + 3 skills
2. **Train (PvE)**: Battle through 7 leagues using limited turns, buy items, level skills
3. **Complete Training**: Defeat Roshan boss to reach Grandmaster league
4. **Compete (PvP)**: Use trained heroes in 5v5 matches and 1v1 duels
5. **Progress Account**: Complete quests to unlock harder content and earn shards

---

## 1. Hero Building System

### 1.1 Avatars

20 avatars across 5 roles, each with distinct stat profiles:

| Role | Identity | Stat Focus |
|------|----------|------------|
| Tank | High survivability | HP, Armor |
| Bruiser | Balanced fighter | HP, ATK, Armor |
| Carry | Physical damage dealer | ATK, Speed |
| Nuker | Magic damage dealer | MP, Power |
| Support | Utility/healing | MP, varied |

**Balance System**: Each avatar has exactly **30 stat units** distributed across 6 stats (HP, MP, ATK, Power, Armor, Speed). Role-specific minimums ensure distinct profiles while the unit budget ensures statistical parity.

See `lib/moba/game/avatars.ex` for the unit calculation: `avatar_stat_units()` and `avatar_minimum_stats()`.

**Avatar Stats**:
- **Base stats**: HP, MP, ATK, Power, Armor, Speed (set at creation)
- **Per-level scaling**: HP/level, MP/level, ATK/level (varies by role)
- **Ultimate skill**: Each avatar has a predefined ultimate ability

**Unlocking**: Some avatars require shards to unlock. Base avatars (no `level_requirement`) are available to new players. See `AvatarQuery.base_current()`.

### 1.2 Skills

Heroes have exactly 4 skills:
- **3 chosen skills**: Selected during hero creation from available pool
- **1 ultimate**: Automatically assigned based on avatar

**Skill Properties**:
- `mp_cost`: Mana required to cast
- `cooldown`: Turns before reuse
- `duration`: For buffs/debuffs
- `passive`: Auto-triggers vs requires activation
- `ultimate`: Avatar-specific, more powerful

**Skill Leveling**:
- Skill points earned on **even hero levels** (2, 4, 6... up to 28 = 14 total points)
- Maximum levels: Normal skills (5), Ultimate skills (3)

| Skill Type | Current Level | Required Hero Level |
|------------|---------------|---------------------|
| Normal | 1 → 2 | Any |
| Normal | 2 → 3 | 6 |
| Normal | 3 → 4 | 10 |
| Normal | 4 → 5 | 14 |
| Ultimate | 1 → 2 | 10 |
| Ultimate | 2 → 3 | 20 |

See `lib/moba/game/skills.ex` → `can_level_skill?/2`.

**Unlocking**: Some skills require shards. Base skills (no `level_requirement`) available to new players.

### 1.3 Items

**Inventory**: Maximum 6 items per hero

**Rarity Tiers** (see `@items_base_price` in `constants.ex`):

| Rarity | Price | Multiplier |
|--------|-------|------------|
| Normal | 400 gold | 1x |
| Rare | 1,200 gold | 3x |
| Epic | 2,400 gold | 6x |
| Legendary | 4,800 gold | 12x |

**Full legendary build**: 6 × 4,800 = 28,800 gold

**Transmutation**: Combine lower-tier items into higher-tier:
- 3 Normal → 1 Rare
- 2 Rare → 1 Epic  
- 2 Epic → 1 Legendary

**Boots Rule**: Only ONE boots item contributes to speed (no stacking). Boots codes: `arcane_boots`, `phase_boots`, `tranquil_boots`, `boots_of_travel`, `boots_of_speed`.

**Item Types**:
- **Active items**: Require MP, have cooldowns, manually triggered
- **Passive items**: Auto-activate when conditions met

**Selling**: 90% refund (100% if hero is finished training)

---

## 2. Battle Engine

All battles (PvE training, league challenges, PvP matches, duels) use the same turn-based engine.

### 2.1 Turn Structure

**Attack Order**: Determined by Speed stat
- `speed` value = percentage chance of attacking first
- 80 Speed = 80% chance of going first
- Both combatants roll; higher Speed has better odds

**Turn Processing Pipeline** (see `lib/moba/engine/core/processor.ex`):
1. `apply_buffs()` — Apply attacker's active buffs
2. `apply_debuffs()` — Apply defender's active debuffs  
3. `apply_permanent_skill()` — Skills that trigger every turn
4. `calculate_atk()` — Finalize attack stat
5. `attack()` — Execute skill/item/basic attack
6. `tick_cooldowns()` — Decrement all cooldowns by 1
7. `passives()` — Trigger passive skills/items
8. `increases_and_reductions()` — Apply Power buffs, armor reduction
9. `apply_attacker_debuffs()` — Debuffs on the attacker
10. `apply_defender_buffs()` — Buffs on the defender
11. `defend()` — Calculate damage mitigation
12. `final_effects()` — Effects that bypass reductions
13. `finish()` — Finalize HP/MP, check for death

**MP Regeneration**: `@turn_mp_regen_multiplier` (2% of max MP per turn)

### 2.2 Damage System

**Damage Types** (see `Engine.damage_types()`):
- **Normal**: Physical damage, affected by normal Power, reduced by armor
- **Magic**: Magic damage, affected by magic Power, reduced by armor
- **Pure**: Bypasses invulnerability, still reduced by armor

**Power** (damage multiplier):
- Stacks **additively** across all sources
- 30 Power from buff + 20 Power from item = 50% extra damage
- Calculated as: `damage + (damage × power / 100)`

**Armor** (damage reduction):
- Reduces incoming damage by percentage equal to armor value
- **Caps at 90%** (armor > 90 still only reduces 90%)
- Can go negative (increases damage taken)

**Armor Pierce**: Converts negative defender armor into bonus damage for attacker

### 2.3 Status Effects

Boolean flags on the Battler (see `lib/moba/engine/schema/battler.ex`):

| Effect | Behavior |
|--------|----------|
| `stunned` | Prevents attacking, interrupts charging skills |
| `silenced` | Forces basic attack only, interrupts charging |
| `disarmed` | Blocks normal damage type |
| `invulnerable` | Blocks all damage except pure |
| `physically_invulnerable` | Blocks only normal damage |
| `inneffectable` | Clears and prevents stun/silence/disarm |
| `evaded` | Attack missed (no damage) |
| `executed` | Instant kill (HP → 0) |
| `immortal` | HP cannot drop from damage |
| `null_armor` | Ignores armor for damage reduction |

### 2.4 Evade Mechanic

Speed above 100 grants evasion chance (see `lib/moba/engine/core/helper.ex` → `can_evade?/1`):
- **1% evade chance per 1 Speed above 100**
- Only triggers on **non-ultimate skills**
- Only blocks **normal (physical) damage** — magic damage still applies
- Has internal cooldown (can't evade consecutive turns)

Example: 120 Speed = 20% chance to evade physical damage from non-ultimate skills

### 2.5 Special Skill Mechanics

**Charging Skills (Double Skills)**:
- Take 2 turns to complete
- Turn 1: Hero is "charging" (vulnerable)
- Turn 2: Full effect applies
- **Interrupted by stun or silence**
- Many charging skills have defensive effects on turn 1 (partial damage, cooldown reset) to mitigate the vulnerability

**Delayed Skills**:
- Cast on turn N, effect applies on turn N+1
- Attacker can use another skill on turn N+1

**Permanent Skills**:
- Applied every attacking turn until removed

### 2.6 Buff/Debuff System

Four buff/debuff arrays on each battler:
- `buffs`: Self-cast positive effects (applied each turn)
- `debuffs`: Negative effects on defender (applied each turn)
- `defender_buffs`: Positive effects cast on defender
- `attacker_debuffs`: Negative effects on self

**Duration**: Ticks down each turn, removed when ≤ 0

**Stacking**: Same-type effects stack additively (Power, Armor, ATK bonuses)

---

## 3. PvE Training System

Training is the hero progression mode where players battle through leagues to reach Grandmaster.

### 3.1 Turn Economy

Heroes have limited turns to complete training. See `constants.ex` → `total_pve_turns/1`:

| PvE Tier | Total Turns |
|----------|-------------|
| 0 (Initiate) | 15 |
| 1 (Novice) | 20 |
| 2+ (Adept and above) | 25 |

**Actions per turn**:
- **Battle**: Fight a target, earn XP + gold on victory
- **Meditate**: Passive XP farming (safer, less reward)
- **Mine**: Passive gold farming (safer, less reward)

**Passive Farm Range** (see `farm_per_turn/1`):
| PvE Tier | Farm Range per Turn |
|----------|---------------------|
| 0 | 800-1,200 |
| 1 | 850-1,200 |
| 2 | 900-1,200 |
| 3 | 950-1,200 |
| 4+ | 1,000-1,200 |

### 3.2 Target System

Targets are bot heroes generated based on the player's current "total farm" (XP + gold earned).

**Target Difficulties**:

| Difficulty | Reward | Bot Quality |
|------------|--------|-------------|
| Weak | 500 (tier 0-1) | Fewer skills, weaker items |
| Moderate | 600 (tier 0-1), 500 (tier 2+) | Medium build |
| Strong | 600 | Full skills, best items |

See `pve_battle_rewards/2` in `constants.ex`.

**Target Distribution by PvE Tier**:
| Tier | Weak | Moderate | Strong |
|------|------|----------|--------|
| 0 | 3 | 3 | 0 |
| 1 | 3 | 6 | 0 |
| 2 | 0 | 6 | 3 |
| 3 | 0 | 3 | 6 |
| 4+ | 0 | 0 | 9 |

**Target Refresh**: Higher PvE tiers unlock more refreshes (see `refresh_targets_count/1`):
| PvE Tier | Refreshes |
|----------|-----------|
| 0-3 | 5 |
| 4 | 5 |
| 5 | 10 |
| 6 | 15 |
| 7 | 20 |

### 3.3 League Progression

7 leagues from Bronze to Grandmaster (see `@leagues` in `constants.ex`):

| Tier | League | Base Level Range |
|------|--------|------------------|
| 0 | Bronze | 3-6 |
| 1 | Silver | 6-9 |
| 2 | Gold | 9-12 |
| 3 | Platinum | 13-16 |
| 4 | Diamond | 17-20 |
| 5 | Master | 22-25 |
| 6 | Grandmaster | 25+ |

**Steps per League**: Each league has multiple steps to complete before advancing:
- Bronze: 2 steps
- Silver: 3 steps
- Gold: 4 steps
- Platinum: 5 steps
- Diamond: 5 steps
- Master: 1 step (boss fight)

**League Challenges**: Battle bot defenders that get stronger per step. Defender level and difficulty increase with each step.

**League Win Bonus**: `@league_win_bonus` = 2,000 gold + XP per advancement

**Max Available League** (based on PvE tier, see `max_available_league/1`):
| PvE Tier | Max League |
|----------|------------|
| 0 | Diamond (tier 4) |
| 1 | Master (tier 5) |
| 2+ | Grandmaster (tier 6) |

### 3.4 Roshan Boss Fight

Roshan is the final boss at Master League (tier 5).

**Boss Mechanics**:
- Level 25, League Tier 6, "boss" difficulty
- **Passive ability**: +Armor and +Power every turn
- This creates a **DPS check**—slow builds get overwhelmed as Roshan scales

**Attempts**:
- 2 chances to defeat Roshan
- If you lose attempt 1: Roshan regenerates **50% of max HP** (`@boss_regeneration_multiplier`)
- If you lose attempt 2: Hero finishes at Master League (not Grandmaster)

**Victory Bonus**: `@boss_win_bonus` = 2,000 gold + XP

**Design Intent**: Roshan filters out suboptimal builds that are too slow or defensive. Only heroes with sufficient burst damage can reach Grandmaster, ensuring Arena heroes are competitively viable.

### 3.5 Death & Buyback

When a hero dies in training:

**Gold Buyback**:
- Cost: Current level × `@buyback_multiplier` (10) gold
- **Reduces Total Farm** (hurts ranking)
- Always available

**Shard Buyback**:
- Cost: 5% of current shards (minimum `@shard_buyback_minimum` = 5)
- **Preserves Total Farm** (no ranking penalty)
- Only available if:
  - Player PvE tier > 3
  - Hero league tier < 5 (Master)
  - Player has enough shards

**Strategic Implication**: Shard buyback enables "perfect runs" (60K total farm) by avoiding gold penalties. Players need to progress their account (earn shards in Arena) to maximize PvE performance.

### 3.6 Hero Completion

A hero finishes training when:
- `pve_current_turns == 0`
- `pve_total_turns == 0`  
- `boss_id == nil` (boss defeated or not applicable)
- Hero is either dead, reached max available league, or in Master League

**On Completion**:
- `finished_at` timestamp set
- Hero becomes available for Arena **immediately**
- Hero becomes available to **other players' teams** after 30 days (`@available_hero_days`)
- PvE ranking updated based on total farm + completion time

### 3.7 Perfect Run (60K Farm)

The maximum achievable farm is `@max_total_farm` = 60,000 (30K XP + 30K gold).

**Achieving Perfect Runs**:
- Battle all Strong targets without dying
- Use shard buyback if death occurs
- Optimal skill leveling and item purchasing order

**Note**: One meta involves using Meditation to gain extra XP to offset gold surplus (since battles give equal XP/gold but max gear costs 28,800 gold, leaving gold headroom). This can result in higher effective power than pure 60K farm builds.

---

## 4. PvP Arena System

The Arena is where trained heroes compete. Two modes: 5v5 Matches and 1v1 Duels.

### 4.1 Team Management

Before competing in matches, players manage teams of 5 heroes.

**Team Schema** (see `lib/moba/game/schema/team.ex`):
- `name`: Custom team name
- `pick_ids`: Array of hero IDs (order matters for battle sequence)
- `defensive`: Boolean - if true, used when defending; if false, used when attacking
- `used_count`: Tracks times picked in manual matches

**Team Features**:
- Create multiple named teams
- Add heroes from:
  - Own finished training heroes
  - Top 100 public heroes (available after `@available_hero_days` = 30 days)
- Reorder heroes within team (affects battle order—first hero fights first)
- Mark teams as "Defensive" (automatically used when opponent attacks you)

**Offensive vs Defensive Teams**:
- When you initiate a match (attacker): Your non-defensive team is used
- When opponent attacks you (defender): Your defensive team is used
- Allows different strategies for attacking vs defending

**Team Edit UI**: `lib/moba_web/live/arena_live/edit.ex`

### 4.2 5v5 Matches

**Setup**:
- Each player's team of 5 heroes fights
- Uses saved team if available, otherwise auto-selects heroes
- **Auto-fill**: If player has fewer than 5 heroes, remaining slots filled with bot heroes

**Auto-fill Logic** (see `lib/moba/game/arena.ex` → `match_pick_auto_fill_ids/2`):
- For Plebs (tier 0): Uses trained heroes, fills remaining with `Heroes.pvp_bots()`
- For higher tiers: Prioritizes Grandmaster heroes, fills with bot heroes
- Ensures new players can compete even without 5 trained heroes

**Battle Flow**:
- Sequential 1v1 battles
- Winner stays and fights next opponent hero
- **Carryover**: Winner restores `current_hp + (total_hp × 0.2)` and `current_mp + (total_mp × 0.2)`
- Buffs/debuffs **cleared** between battles (fresh state)
- Match ends when one team loses all 5 heroes

**Winner Advantage**: The winner is always the **attacker** in the next battle, gaining first-attack advantage.

**Daily Limit**: `@daily_match_limit` = 30 matches per day

**Match Modes**:
- **Auto**: System creates matches every 30 minutes (see `lib/moba/conductor.ex` → `season_tick!/0`)
- **Manual**: Player initiates, earns `@matchmaking_shards` = 20 shards per match

**Manual Match Strategy**: 
- Each manual victory can replace an auto loss
- But manual losses can also replace wins
- Players can play all 30 manually or let auto-play handle it

### 4.3 Bot Players for Matchmaking

For new arena entrants with low/zero season points, **bot players** serve as guaranteed matchmaking opponents to ensure new players always have matches available.

**Bot Player Structure** (see `lib/moba/game/schema/bot_options.ex`):
- Players with `bot_options` set are bots
- Have `name`, `tier`, and `codes` (avatar codes they use)
- Queried via `PlayerQuery.bots()` and `Players.bot_ranking()`

**Matchmaking Fallback**:
- `Players.matchmaking_opponent/1` first tries to find real players
- For Plebs: `pleb_opponents/3` searches within ±100/+50 point range
- If no real opponent found: falls back to bot players
- Ensures new players always have someone to fight

**Bot Player Creation**: Manually created in production database (not seeded automatically).

### 4.4 1v1 Duels

**Types**:
- **Live Duels**: Real-time pick/battle against online opponent
- **Season Duels (Async)**: Challenge any player, their heroes are played automatically

**Duel Structure**:
- 2 battles per duel
- Alternating picks ensure fairness:
  - Battle 1: You pick first
  - Battle 2: Opponent picks first

**Pick Phases**:
1. `player_first_pick` — You pick hero for battle 1
2. `opponent_first_pick` — They pick hero for battle 1
3. `player_battle` — Battle 1 executes
4. `opponent_second_pick` — They pick hero for battle 2
5. `player_second_pick` — You pick hero for battle 2
6. `opponent_battle` — Battle 2 executes
7. `finished`

**Pick Timer**: `@duel_timer_in_seconds` = 60 seconds. **Auto-pick on timeout** (system picks for you).

**Season Duels**: Players can farm unlimited season points via async duels. However, auto 5v5 match losses eventually offset these gains, creating equilibrium.

**Important**: In async duels, opponent heroes are **real player data** played automatically. Players should configure `skill_order` and `item_order` on their heroes to optimize AI play.

### 4.5 Bracket System

Three PvP brackets with daily promotion/demotion:

| Bracket | Description |
|---------|-------------|
| Plebs | Default bracket, majority of players |
| Shadows | Top performers from Plebs |
| Immortals | Elite bracket, compete for #1 |

**Daily Reset Logic** (see `lib/moba/conductor.ex` → `pvp_tick!/0`):

**Plebs**:
- Top 5 by `daily_wins` → Promote to Shadows

**Shadows**:
- Top 4 by `daily_wins` → Promote to Immortals
- Bottom 5 by `daily_wins` → Demote to Plebs
- Rest stay in Shadows

**Immortals**:
- #1 by `daily_wins` → Stays as "The Immortal"
- Rest → Demote to Shadows

### 4.6 Point System (ELO-like)

Points gained/lost depend on rating difference between players.

**Duel Points** (see `victory_duel_points/2`, `defeat_duel_points/2`, `tie_duel_points/2`):

| Scenario | Points |
|----------|--------|
| Victory (similar rating, ±40) | 5 |
| Victory (underdog, opponent higher) | `ceil(150 / abs(diff))` (minimum 2) |
| Victory (favorite, opponent lower) | `ceil(diff × 0.15)` |
| Auto duel victory | 3× normal points |
| Tie (you're stronger) | `-ceil(diff × 0.05)` |
| Tie (you're weaker) | `+ceil(diff × 0.05)` |

**Maximum difference**: `@maximum_points_difference` = 200. No points if gap exceeds this.
**Minimum points**: `@minimum_duel_points` = 2

**Match Points** (see `victory_match_points/1`, `defeat_match_points/1`):
- Victory (similar): 2 points
- Victory (underdog): `ceil(50 / abs(diff))`
- Victory (favorite): `ceil(diff × 0.05)`
- Defeat: `ceil(victory_match_points(-diff) × 1.1)` or 2 minimum

**Long-term Behavior**: Points deflate/reach equilibrium. Players with very high points lose significantly when defeated, preventing runaway inflation.

### 4.7 Immortal Streak

Consecutive days as #1 in Immortals bracket.

**Streak Penalty**: `@immortal_streak_multiplier` = 1% stat reduction per streak in matches
- 5-streak = 5% stat penalty
- Makes maintaining high streaks progressively harder

**Season Score Contribution**: `100 × best_immortal_streak` (see Season Ranking below)

**Target Streak**: Currently balanced around 5-6 days being achievable with effort.

---

## 5. Progression Systems

### 5.1 Account Structure

Three-tier hierarchy:

| Entity | Scope | Persists Across |
|--------|-------|-----------------|
| **User** | Permanent account | Everything |
| **Player** | Per-season instance | Season reset |
| **Hero** | Per-training run | Never (individual runs) |

**User** (see `lib/moba/accounts/schema/user.ex`):
- `shard_count`: Account currency
- `unlocks`: Purchased avatars/skills/skins
- Discord integration

**Player** (see `lib/moba/game/schema/player.ex`):
- `pvp_tier`: Current bracket (0-2)
- `pvp_points`: ELO-like rating
- `pve_tier`: Account progression (0-7)
- `hero_collection`: Best hero per avatar for display
- `ranking`, `season_ranking`: Leaderboard positions
- `daily_wins`, `daily_matches`: Reset daily

**Hero** (see `lib/moba/game/schema/hero.ex`):
- All training state (level, skills, items, gold, XP)
- League progression
- Battle stats

### 5.2 PvE Tiers (Account Progression)

8 tiers representing mastery (see `@pve_tiers` in `constants.ex`):

| Tier | Title | Requirement |
|------|-------|-------------|
| 0 | Initiate | Starting tier |
| 1 | Novice | 2 avatars on Platinum+ |
| 2 | Adept | 5 avatars on Platinum+ |
| 3 | Veteran | 10 avatars on Platinum+ |
| 4 | Expert | 15 avatars on Platinum+ |
| 5 | Master | 20 avatars on Master+ |
| 6 | Grandmaster | 20 avatars on Grandmaster |
| 7 | Invoker | 20 avatars on Grandmaster with 60K farm |

**Cumulative Tracking**: Completing a higher tier (e.g., Master) also counts toward lower tier requirements (e.g., Platinum+).

### 5.3 Quest Rewards

Each tier advancement grants rewards (see `lib/moba/game/quests.ex`):

| Tier | Shards | Bonus |
|------|--------|-------|
| 1 (Novice) | 200 | +1,000 starting gold |
| 2 (Adept) | 300 | — |
| 3 (Veteran) | 400 | — |
| 4 (Expert) | 500 | 5 target refreshes |
| 5 (Master) | 1,000 | 10 target refreshes |
| 6 (Grandmaster) | 2,500 | 15 target refreshes |
| 7 (Invoker) | 5,000 | 20 target refreshes |

**Starting Gold** (see `initial_gold/1`):
- Tier 0: `@initial_gold` = 800
- Tier 1+: `@veteran_initial_gold` = 2,000

### 5.4 Rankings

**Daily Ranking** (`@daily_ranking_limit` = 50):
- Sorted by: `daily_wins` DESC, then `pvp_points` DESC
- Resets daily with bracket recalculation

**Season Ranking** (`@season_ranking_limit` = 50):
- Formula: `(100 × best_immortal_streak) + (100 × pve_tier) + pvp_points`
- Secondary sort: `total_wins`
- Only includes players active after cutoff date

**PvE Ranking** (`@pve_ranking_limit` = 200):
- Sorted by: `total_gold_farm + total_xp_farm` DESC, then completion time
- Only finished heroes in Master/Grandmaster league

---

## 6. Economy

### 6.1 Gold (Hero Currency)

Per-hero currency, not shared across heroes.

**Sources**:
- Battle victories: 500-600 per target
- Mining: 800-1,200 per turn
- League advancement: 2,000 bonus
- Boss victory: 2,000 bonus

**Uses**:
- Item purchases (400-4,800 per item)
- Gold buyback (level × 10)

**Effective Cap**: ~30K (full legendary build costs 28,800)

### 6.2 Shards (Account Currency)

Permanent currency on User account.

**Sources**:
- Quest completion: 200-5,000
- Manual matchmaking: `@matchmaking_shards` = 20 per match

**Uses**:
- Unlock avatars: 150 shards
- Unlock skills: 100 shards
- Unlock skins: 500 (Master) or 1,000 (Grandmaster)
- Shard buyback: 5% of current (minimum 5)

### 6.3 Tavern (Unlock Shop)

Permanent unlock store using shards.

**Avatar Unlocks**: 150 shards
- Unlocks avatar for hero creation

**Skill Unlocks**: 100 shards
- Unlocks skill for hero creation

**Skin Unlocks**: 
- 500 shards (requires owning avatar at Master league)
- 1,000 shards (requires owning avatar at Grandmaster league)

---

## 7. Bot System

Bots serve as training targets, league defenders, and team fillers.

### 7.1 Bot Generation

Bots are pre-generated via `mix bots` (see `lib/moba/conductor.ex` → `regenerate_bots!/1`).

**PvE Bots** (per avatar, per level 0-35):
- 1 "weak" bot
- 1 "moderate" bot
- 3 "strong" bots (level > 0)

**PvP Bots** (per avatar):
- 10 "pvp_master" bots (level 24, tier 5)
- 10 "pvp_grandmaster" bots (level 26, tier 6)

### 7.2 Bot Difficulty

| Difficulty | Skills | Items | Total Farm |
|------------|--------|-------|------------|
| weak | 1 from build | Normal order | 0-800 |
| moderate | 2 from build | Shuffled order | 800-1,600 |
| strong | Full build (50%) or 2 | Reversed (strongest first) | 1,600+ |
| pvp_master | Full build | Full legendaries | ~24,000 |
| pvp_grandmaster | Full build | Random legendaries + epics | ~30,000 |

### 7.3 Bot Builds

Bots use **predefined builds** from `lib/moba/game/builds.ex`:
- 2 builds per avatar
- Based on historical best player builds
- **Different from starter builds** (which are simpler for new players)

### 7.4 Bot Turn AI

Bots follow `skill_order` and `item_order` arrays (see `lib/moba/engine/core/processor.ex` → `get_resource_from_order/3`):

1. Iterate through `skill_order`
2. Use first skill that passes `should_use?/4`:
   - Has MP available
   - Not on cooldown
   - Not a passive skill
3. If no skill usable, use basic attack
4. Same process for `item_order` (active items)

**Smart Behavior**: Bots skip certain skills against high-armor targets (`next_armor >= 100`).

### 7.5 Bot Appearances

| Context | Bot Type |
|---------|----------|
| Training targets | PvE bots (weak/moderate/strong) |
| League challenges | PvE bots (scaling difficulty) |
| Match team filler | PvP grandmaster bots |
| Auto duels | Real player heroes played by AI |

**Important**: In season duels (async), opponents are **real player heroes** controlled automatically—not bots. Players should configure their heroes' `skill_order` and `item_order` to optimize how the AI plays them.

---

## 8. Balance Philosophy

### 8.1 Avatar Balance

**30-Unit Budget**: Every avatar has exactly 30 stat units distributed across HP, MP, ATK, Power, Armor, Speed. This ensures no avatar is statistically superior overall.

**Role Minimums**: Each role has minimum stats that create distinct identities:
- Tanks: Higher min HP, Armor
- Carries: Higher min Speed, ATK
- Nukers: Higher min MP, Power

**Per-Level Scaling**: Different growth rates create early-game vs late-game avatars.

### 8.2 Skill/Item Balance

**Winrate Tracking**: Admin dashboard shows winrates per skill/item/avatar across brackets (Plebs/Shadows/Immortals/Elite).

**Target Winrate**: **66%** for attackers (not 50%)
- Attacker advantage (picks second, sees opponent team) is significant
- Arena stats have converged to ~66% over years of play

**Balance Method**: If something consistently over/underperforms:
- Overperforming: Nerf the resource directly
- Underperforming: Usually buff the resource (prefer buffs over nerfs to alternatives)

### 8.3 Roshan as Build Filter

Roshan's +armor/+power per turn passive serves as a **build validator**:
- Filters out excessively slow/defensive builds
- Ensures Grandmaster heroes have viable burst damage
- Prevents Arena from being dominated by stall strategies

### 8.4 Speed Meta

**100 Speed is effectively required** for most builds:
- Attacking first is a major advantage
- Exception: Tank builds or regeneration-based strategies

**Low-Speed Avatars**: Compensate by purchasing better boots (Boots of Travel for +25 Speed).

**Evade Mechanic**: Rewards speed above 100 with evasion chance, creating incentive to stack speed beyond the "required" amount.

---

## 9. Async Competition Model

### 9.1 Persistent Historical Opponents

**All finished heroes remain in the game forever**:
- Past top players' heroes continue competing
- New players battle against historical best
- Creates persistent challenge even without active opponents

**Implications**:
- Reaching #1 requires beating accumulated years of optimization
- Competitive players typically engage for 2-3 weeks, return periodically
- Game remains challenging without constant new content

### 9.2 Season Duels (Infinite Farming)

Players can farm unlimited season points via async 1v1 duels:
- Challenge any player's heroes
- AI plays both sides using `skill_order`/`item_order`
- No daily limit on season duels

**Equilibrium Mechanism**:
- Auto 5v5 matches (30/day) eventually result in losses
- High-point players lose significant points on defeat
- Prevents runaway point inflation

---

## 10. Technical Notes

### 10.1 Key Files

| System | Primary Files |
|--------|---------------|
| Game orchestration | `lib/moba.ex`, `lib/moba/game.ex` |
| Battle engine | `lib/moba/engine.ex`, `lib/moba/engine/core/processor.ex` |
| Skill definitions | `lib/moba/engine/core/spell.ex` |
| Effect functions | `lib/moba/engine/core/effect.ex` |
| Constants | `lib/moba/constants.ex` |
| Scheduled tasks | `lib/moba/conductor.ex` |
| Bot generation | `lib/moba/game/builds.ex` |

### 10.2 Scheduled Tasks

| Task | Frequency | Function |
|------|-----------|----------|
| Auto matchmaking | Every 30 min | `Conductor.season_tick!/0` |
| Daily reset | Daily | `Conductor.pvp_tick!/0` |
| PvE ranking | On hero finish | `Moba.rank_finished_heroes/0` |

### 10.3 Extension Points

**Adding new Avatar**:
1. Create DB record with 30 units distributed
2. Add images
3. Create ultimate skill
4. Run `mix resources` to regenerate

**Adding new Skill**:
1. Create DB record
2. Add pattern match in `lib/moba/engine/core/spell.ex` → `effects_for/2`
3. Use existing Effect functions or add new ones

**Adding new Status Effect**:
1. Add field to `lib/moba/engine/schema/battler.ex`
2. Add Effect function to apply it
3. Add handling in `lib/moba/engine/core/processor.ex`
4. Add logging in `lib/moba/engine/core/logger.ex`

---

## Appendix A: Key Constants

All values from `lib/moba/constants.ex`:

### General
| Constant | Value | Description |
|----------|-------|-------------|
| `@base_hero_count` | 6 | Base heroes available |
| `@turn_mp_regen_multiplier` | 0.02 | MP regen per turn (2%) |
| `@shard_buyback_minimum` | 5 | Min shards for buyback |

### PvE
| Constant | Value | Description |
|----------|-------|-------------|
| `@total_pve_turns` | 25 | Base turns (tier 2+) |
| `@turns_per_tier` | 5 | Turns per league tier |
| `@base_xp` | 600 | XP for level 2 |
| `@xp_increment` | 50 | Additional XP per level |
| `@initial_gold` | 800 | Starting gold (tier 0) |
| `@veteran_initial_gold` | 2,000 | Starting gold (tier 1+) |
| `@items_base_price` | 400 | Normal item price |
| `@buyback_multiplier` | 10 | Gold buyback = level × 10 |
| `@max_total_farm` | 60,000 | Perfect run target |
| `@pve_ranking_limit` | 200 | Top heroes ranked |

### League
| Constant | Value | Description |
|----------|-------|-------------|
| `@platinum_league_tier` | 3 | Platinum = tier 3 |
| `@master_league_tier` | 5 | Master = tier 5 |
| `@max_league_tier` | 6 | Grandmaster = tier 6 |
| `@league_win_bonus` | 2,000 | Gold+XP per advancement |
| `@boss_regeneration_multiplier` | 0.5 | Roshan heals 50% |
| `@boss_win_bonus` | 2,000 | Bonus for beating Roshan |

### PvP
| Constant | Value | Description |
|----------|-------|-------------|
| `@daily_match_limit` | 30 | Matches per day |
| `@matchmaking_shards` | 20 | Shards per manual match |
| `@duel_timer_in_seconds` | 60 | Pick timeout |
| `@turn_timer_in_seconds` | 30 | Battle turn timeout |
| `@immortal_streak_multiplier` | 0.01 | 1% stat penalty per streak |
| `@daily_ranking_limit` | 50 | Daily leaderboard size |
| `@season_ranking_limit` | 50 | Season leaderboard size |
| `@maximum_points_difference` | 200 | Max ELO diff for points |
| `@minimum_duel_points` | 2 | Min points per duel |
| `@available_hero_days` | 30 | Days before hero public |

---

## Appendix B: Avatar Reference

20 avatars with role distribution:

| Role | Avatars |
|------|---------|
| Tank | Abaddon, Doom, Dragon Knight |
| Bruiser | Tusk, Sven, Axe |
| Carry | Troll Warlord, Templar Assassin, Sniper, Weaver, Juggernaut, Phantom Assassin |
| Nuker | Lina, Puck, Pugna, Rubick, Techies, Tinker |
| Support | Dazzle, Omniknight |