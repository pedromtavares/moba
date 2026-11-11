# BrowserMOBA Product Doc

Last checked against the repository on 2026-11-10. This document describes the current game. Visual and interaction principles are in [DESIGN.md](DESIGN.md).

## Overview

BrowserMOBA is a free-to-play, open-source turn-based RPG that brings MOBA-style strategic gameplay to casual browser gaming. Players train three-hero rosters or solo heroes through PvE leagues, then compete in 3v3 Arena matches and async or live 1v1 duels.

### Content Snapshot

Counts come from [`priv/repo/seed_catalog.json`](../priv/repo/seed_catalog.json), the fresh-install catalog. Count enabled playable resources by distinct code, rather than counting level variants or generated balance versions.

| Content | Current catalog |
|---------|-----------------|
| Playable avatars | 24 across 5 roles (10 starter avatars and 14 unlockable avatars) |
| Selectable normal skills | 24, available to everyone |
| Avatar ultimates | 24, one predefined ultimate per playable avatar |
| Items | 30: 6 Normal, 6 Rare, 9 Epic, 9 Legendary |
| Cosmetic skins | 48: one Master and one Grandmaster skin for each playable avatar |
| Training leagues | 7, Bronze through Grandmaster |
| Account ranks | 8, Initiate through Invoker |
| Arena brackets | 3: Plebs, Shadows, Immortals |

The catalog also includes the non-playable Boss avatar and four disabled boss skills. The 196 skill records include level variants and boss skills. The 48 enabled player abilities consist of 24 selectable normal skills and 24 avatar ultimates.

### Design Philosophy

- **Simple mechanics, deep strategy**: The game optimizes for straightforward rules with emergent complexity
- **Casual sessions**: Turn-based training and async competition, playable in short browser sessions
- **Async competition**: Eligible trained heroes can fight using saved combat orders while their owners are away
- **No pay-to-win**: All content unlockable through gameplay, no real-money purchases

### Core Game Loop

1. **Draft** three different unlocked avatars, or choose one in Solo 1v1. Each hero takes three normal skills from a preset or custom build and gets its avatar's ultimate.
2. **Train** by fighting targets, spending skill points, and building each hero's inventory.
3. **Advance** through league challenges and defeat Roshan to reach Grandmaster when the account rank permits it.
4. **Compete** with eligible trained heroes in 3v3 Arena matches and 1v1 duels.
5. **Progress** through account ranks, earn Shards, and unlock avatars and skins in Base.

---

## 1. Hero Building System

### 1.1 Avatars

24 playable avatars across 5 roles, each with distinct stat profiles:

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

**Unlocking**: 10 base avatars (no `level_requirement`) are available to new players. The other 14 are unlockable. Base offers Tinker as a free unlock through Discord connection; standard avatar unlocks cost 150 shards. See `AvatarQuery.base_current()`, `Accounts.Unlocks`, and `AuthController.callback/2`.

### 1.2 Skills

The playable catalog contains 24 normal skills and 24 avatar ultimates. Heroes have exactly 4 skills:

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

**Availability**: All 24 normal skills are available to guests and registered players. Avatar ultimates come with the avatar.

### 1.3 Items

30 enabled items across four rarity tiers: 6 Normal, 6 Rare, 9 Epic, and 9 Legendary. The in-game place to buy and transmute hero items is called the **Shop**; account unlocks live in the **Base** collection.

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

**Selling**: Full gold refund in solo and team training, including after training ends.

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
- Has a 3-turn cooldown. Echo Stomp bypasses Evade and does not trigger its cooldown.

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

Team 3v3 is the default, including for guests. Registered players can switch to Solo 1v1. Both modes use the same combat engine and leagues, but differ in how players spend turns, earn rewards, and advance.

### 3.1 Drafting and loadouts

- Guests draft on `/start`. Registered players draft on `/new` and can choose solo at `/new/solo`. The roster suggests Juggernaut, Lina, then Tusk when those avatars are available. A registered team name defaults to the username and is inherited by its heroes. Guest heroes use avatar names.
- Each hero gets at least 1,200 starting gold. Novice and higher accounts start with 2,000 per hero.
- The default combat order puts a castable ultimate first, followed by the chosen active skills. Passive skills trigger through combat rules. Players can edit combat orders separately from the display order.
- Team training enables Auto Buy by default. Nukers open with Tranquil Boots and Vanguard. Other roles open with Arcane Boots and Shadow Blade. Auto Buy then follows the build's item order and upgrades or replaces eligible Rare and Epic items with Legendaries when it can afford them. The opening boots and items manually bought or transmuted by the player are protected from automation.
- Team battles can be played turn by turn or automated one battle at a time or across a full encounter. Solo training uses manual shopping and battle controls.

### 3.2 Turns, targets, and rewards

Solo has one hero and can spend turns fighting, meditating for XP, or mining for gold. Team training shares a turn pool, has no meditation or mining, and sends only the selected hero into a normal target battle. Both modes start with five turns available and unlock up to five more per league stage from a reserve of 15 turns for Initiate, 20 for Novice, and 25 for Adept and above.

Each roster member gets three targets based on their own earned XP and gold. Target pools refresh for the full roster after an encounter. Expert and higher ranks also get manual refreshes, which reroll the selected hero's targets in team training.

| Account rank | Team target mix | XP and gold per solo target win, before team multiplier |
|--------------|-----------------|-----------------------------------------------------------|
| Initiate | 2 Easy, 1 Medium | Easy 500, Medium 600 |
| Novice | 1 Easy, 2 Medium | Easy 500, Medium 600 |
| Adept | 2 Medium, 1 Hard | Medium 500, Hard 600 |
| Veteran | 1 Medium, 2 Hard | Medium 500, Hard 600 |
| Expert and above | 3 Hard | Hard 600 |

Team rewards are triple the solo amount for each resource. **Shared** splits a normal battle reward across all three heroes. **Focus** gives it to the hero who fought. League and Roshan rewards always split across the roster. Each team hero caps at level 30 and 30,000 earned gold. Excess XP and gold are redirected independently to other heroes with room. A level-30 hero can still fight league challenges, but can no longer start a normal target battle in either reward mode.

### 3.3 League challenges

| Training Rank | Highest available league |
|---------------|--------------------------|
| Initiate | Diamond |
| Novice | Master |
| Adept and above | Grandmaster |

- Solo retains its sequence of one-on-one league battles. Bronze through Diamond have 2, 3, 4, 5, and 5 battles respectively.
- A team advances by winning one 3v3 elimination encounter. It uses the three hardest defender slots from the solo challenge, with an extra earlier slot in the Bronze-to-Silver challenge. Defender scaling uses the midpoint between the roster's average farm and its highest-farm hero.
- A team can start a challenge after spending its current turns or reaching level 30 on all three heroes. All three must be alive and all available skill points must be spent. The survivor starts the next pairing and carries its remaining health and energy forward. The winning team recovers after the challenge.
- A league promotion awards 2,000 XP and 2,000 gold in solo, or a team pool of 6,000 XP and 6,000 gold.

### 3.4 Roshan

Roshan is the final challenge from Master to Grandmaster. In team training he has 10,000 HP and fights the roster in order. Remaining health carries over and initiative is evaluated again for each new pairing using the training Speed rule. If the first attempt fails, he regains up to half his maximum health for the final attempt. Defeating him earns the Grandmaster promotion and a separate boss bonus of 2,000 XP and gold in solo or 6,000 of each across the team. Losing the final attempt leaves the run at Master.

### 3.5 Death, recovery, and Perfect Runs

Gold buyback costs 10 gold per hero level and deducts from recorded gold farm. Eligible players can use Shard buyback below Master to preserve farm. Selling items returns their full gold price without reducing recorded farm. Death itself is not a separate Perfect Run disqualifier. Beginner protection and turn refunds can affect the outcome of a target loss. Resetting a team restarts all three heroes with the same builds.

A completed **Perfect Run** reaches Grandmaster and earns at least 60,000 farm in solo or 60,000 average farm across a team. Each distinct avatar on a qualifying team can count toward Invoker. The in-progress Perfect indicator shows whether the run can still meet that target.

### 3.6 Completion and records

Team members become ordinary finished heroes in the collection. Heroes that meet Arena eligibility can be picked individually or as part of a roster, and completing team training does not create a saved Arena lineup. Finished teams have their own page and leaderboard. Their individual heroes do not enter the solo rankings.

A normal roster target fight is stored as a Battle. Multi-battle roster encounters are stored as training Matches with individual Battles. Solo league challenges retain their solo battle flow.

---

## 4. PvP Arena System

The Arena offers 3v3 team matches and 1v1 duels. Arena Rating is shared across both modes, while daily bracket standings use 3v3 wins.

### 4.1 Lineup management

Arena lineups have three ordered slots. Pick eligible finished heroes individually, load a finished training roster, or use a saved Arena team. Arena teams are separate records and can mix heroes from different training runs. Create and reorder them in `/arena/edit`, or mark a lineup for defense. The match picker also supports repeating the last lineup and dragging heroes into slots.

Manual picks can use the player's finished Platinum-or-higher heroes, eligible public heroes for higher brackets, or available bot picks. Automatic matchmaking requires a registered account at Novice or higher with at least one Grandmaster collection entry or two entries at Master or higher. Bots can fill empty slots. Former five-hero saved lineups use their first three slots. Historical 5v5 matches retain their original replays.

### 4.2 3v3 matches

- An ordered series of one-on-one battles ends when one lineup is eliminated. The survivor starts the next fight with its remaining health and energy plus 20% of each maximum. Temporary effects reset between battles.
- Manual matches start turn-by-turn, with **Auto battle** and **Auto all battles** available. Scheduled matchmaking runs every 30 minutes and plays automatically.
- Arena counts up to 20 matches per day. A manual match can replace an auto match once the daily slots are filled, up to 20 manual matches.
- The first 20 eligible manual 3v3 matches and 1v1 duels combined award 30 Shards each. Using up the reward allowance does not reduce the remaining 3v3 match allowance or cap 1v1 play. For example, 10 manual matches and 10 duels exhaust the reward allowance and leave room for 10 more manual matches.
- The displayed 3v3 win rate uses the account’s latest 100 scored 3v3 matches with a winner, counting matches in which the account was the challenger.

### 4.3 Bot Players for Matchmaking

For new arena entrants with low/zero Arena Rating, **bot players** serve as guaranteed matchmaking opponents to ensure new players always have matches available.

**Bot Player Structure** (see `lib/moba/game/schema/bot_options.ex`):
- Players with `bot_options` set are bots
- Have `name`, `tier`, and `codes` (avatar codes they use)
- Queried via `PlayerQuery.bots()` and `Players.bot_ranking()`

**Matchmaking Fallback**:
- `Players.matchmaking_opponent/1` first tries to find real players
- For Plebs, `pleb_opponents/3` searches from 100 AR below the player to 50 AR above
- If no real opponent found: falls back to bot players
- Ensures new players always have someone to fight

**Bot Player Creation**: Manually created in production database (not seeded automatically).

### 4.4 1v1 Duels

**Types**:
- **Live Duels**: Real-time pick/battle against online opponent
- **Season Duels (Async)**: Matchmake against another account whose heroes follow saved combat orders

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

**Season Duels**: There is no daily play cap. A player chooses actions manually while the async opponent follows saved combat orders. Live and Season Duels do not offer the Auto battle controls.

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
- Top 6 by `daily_wins` → Promote to Shadows

**Shadows**:
- Top 4 by `daily_wins` → Promote to Immortals
- Bottom 6 by `daily_wins` → Demote to Plebs
- Rest stay in Shadows

**Immortals**:
- #1 by `daily_wins` → Stays as "The Immortal"
- Rest → Demote to Shadows

### 4.6 Arena Rating (AR)

Arena Rating (AR) is the shared competitive rating for 3v3 matches and 1v1 duels. Rating gains and losses depend on the game mode, result, and rating difference between players. The internal field remains `pvp_points`.

For the formulas below, `diff` is the opponent’s rating minus the challenger’s rating.

| 1v1 result | Challenger rating change |
|------------|--------------------------|
| Live win, gap below 40 | +5 |
| Live win, challenger favored by 40–200 | `+max(2, ceil(150 / abs(diff)))` |
| Live win, challenger trails by 40–200 | `+ceil(diff × 0.15)` |
| Live loss | The reverse of what the opponent would gain for winning |
| Live draw | `max(2, ceil(abs(diff) × 0.05))`, lost if the challenger is higher rated and gained otherwise |
| Season win | Three times the equivalent live win |
| Season loss | Same loss as in a live duel |
| Season draw | +2 |

A gap above 200 zeros out wins, losses, and live draws. In live duels the other player receives the opposite change. In Season Duels only the challenger’s rating changes.

| 3v3 result | Challenger rating change |
|------------|--------------------------|
| Win, gap below 40 | +2 |
| Win, challenger favored by 40 or more | `+ceil(50 / abs(diff))` |
| Win, challenger trails by 40 or more | `+ceil(diff × 0.05)` |
| Loss, `diff` strictly between −40 and 80 | −2 |
| Other loss | The opponent’s equivalent win value multiplied by 1.1, rounded up and subtracted |

The opponent receives the opposite change in 3v3.

### 4.7 Immortal Streak

Consecutive days as #1 in Immortals bracket.

**Streak Penalty**: `@immortal_streak_multiplier` = 1% stat reduction per streak in matches
- 5-streak = 5% stat penalty
- Makes maintaining high streaks progressively harder

**Season Score Contribution**: 20 points per day of the best Immortal Streak. The current Immortal (Immortals bracket, daily rank #1) also receives a flat 200-point bonus while holding the title.

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
- `unlocks`: Unlocked avatars and skins
- Discord integration

**Player** (see `lib/moba/game/schema/player.ex`):
- `pvp_tier`: Current bracket (0-2)
- `pvp_points`: Arena Rating (AR)
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
| 1 | Novice | Finish one training run on Platinum or higher |
| 2 | Adept | Finish one training run on Master or higher |
| 3 | Veteran | 10 avatars on Platinum+ |
| 4 | Expert | 15 avatars on Platinum+ |
| 5 | Master | 20 avatars on Master+ |
| 6 | Grandmaster | 20 avatars on Grandmaster |
| 7 | Invoker | 20 distinct avatars in Perfect Grandmaster runs |

**Collection vs. progression goals**: The collection covers all 24 playable avatars. Master, Grandmaster, and Invoker still require 20 distinct qualifying avatars, not all 24. Invoker counts distinct avatars from Grandmaster runs with at least 60K solo farm or 60K team average farm.

**Cumulative Tracking**: Completing a higher tier (e.g., Master) also counts toward lower tier requirements (e.g., Platinum+).

### 5.3 Quest Rewards

Each tier advancement grants rewards (see `lib/moba/game/quests.ex`):

| Tier | Shards | Bonus |
|------|--------|-------|
| 1 (Novice) | 200 | Starting gold increases to 2,000 |
| 2 (Adept) | 300 | — |
| 3 (Veteran) | 400 | — |
| 4 (Expert) | 500 | 5 target refreshes |
| 5 (Master) | 1,000 | 10 target refreshes |
| 6 (Grandmaster) | 2,500 | 15 target refreshes |
| 7 (Invoker) | 5,000 | 20 target refreshes |

**Starting Gold** (see `initial_gold/1`):
- Tier 0: `@initial_gold` = 1,200
- Tier 1+: `@veteran_initial_gold` = 2,000

### 5.4 Rankings

**Daily Ranking** (`@daily_ranking_limit` = 50):
- Sorted by: `daily_wins` DESC, then `pvp_points` DESC
- Resets daily with bracket recalculation

**Season Ranking** (`@season_ranking_limit` = 50):
- Formula: Training Rank score + Arena Rating + (20 × best Immortal Streak) + 200 while holding The Immortal title.
- Training Rank scores: Initiate 0, Novice 100, Adept 200, Veteran 300, Expert 400, Master 500, Grandmaster 600, Invoker 700.
- The 200-point title bonus moves to the new Immortal when the daily brackets update. The 20-point-per-day best-streak contribution remains with the player.
- Secondary sort: `total_wins`
- Only includes players active after cutoff date

**Solo and team training rankings**:
- Solo ranks by total farm, then fastest completion. The global board includes eligible recent finishes and qualifying Master or Grandmaster runs within its historical window. League boards begin at Gold and compare finished solo runs in that exact league, including past runs. Grandmaster hero pages show the global board.
- Team ranks finished runs by combined farm, then fastest completion. The board displays average farm per hero, which gives the same order for three-hero rosters. Team members count toward account progression and the collection, independently of solo ranks.
- Profiles use a cached collection with the best eligible finished hero per avatar. Solo and team heroes are ordered by farm, then training time, with solo rank used when available.

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
- Arena: `@matchmaking_shards` = 30 per game for the first 20 eligible manual 3v3 matches and 1v1 duels combined each day

**Uses**:
- Unlock avatars: 150 shards
- Unlock skins: 500 (Master) or 1,000 (Grandmaster)
- Shard buyback: 5% of current (minimum 5)

### 6.3 Base collection unlocks

Select an avatar in Base to see its unlock price or browse its skins.

- Standard avatar unlocks cost 150 shards and make the avatar available in hero creation.
- Connecting Discord unlocks Tinker for free.
- Master skins cost 500 shards and require a completed run with that avatar in Master League or higher.
- Grandmaster skins cost 1,000 shards and require a completed Grandmaster run with that avatar.

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

Eligible completed builds can keep appearing in automatic matches and Season Duels while their owners are offline. Saved combat orders determine how those heroes play.

### 9.2 Season Duels

Season 1v1 matchmakes against another account’s trained lineup and works while the opponent is offline. The player controls their hero and the opponent follows saved orders. Live 1v1 pairs two connected players. Both share Arena Rating with 3v3 and use the same daily Shard allowance for eligible games.

---

## Player Experience

| Screen | Route | Current experience |
|--------|-------|--------------------|
| Guest roster | `/start` | Draft three avatars using presets or custom builds |
| Start training | `/new`, `/new/solo` | Team 3v3 by default, with Solo 1v1 available to registered players |
| Base | `/base` | Account rank progress, collection, paginated pending and finished runs, avatar and skin unlocks |
| Training | `/training` | League progress, roster tabs, target cards, Shop, league and Roshan challenges |
| Battle history / replay | `/battles`, `/battles/:id` | Turn-by-turn resources and effects, battle log, and contextual result actions |
| Arena | `/arena` | Play or resume 3v3 and 1v1, mode-specific history and standings, and a separate Live 1v1 column |
| Arena team builder | `/arena/edit` | Saved teams, defensive lineup, and a paginated hero collection sorted by farm by default |
| Match summary | `/matches/:id` | Shared lineup layout for pre-match selection and completed matches, with health and energy summaries afterward |
| Match battles | `/matches/:match_id/battles` | Cinematic combat and battle navigation. Completed matches open on the final battle by default |
| 1v1 Duel | `/arena/:id` | Picks, timers, results, replays, and chat and rematch for live opponents |
| Player profile | `/player/:player_id`, `/user/:id` | Featured hero, 3v3 and 1v1 history, Season / Team / Hero rankings, and collection |
| Hero and team profiles | `/hero/:id`, `/teams/:id` | Training results, builds, league progress, and rankings. Finished roster runs open their team profile |
| Community | `/community` | Recent Players, Top Players, Top Teams, and Top Heroes. Admins also see activity totals and Arena Stats |
| Library | `/library` | Avatars, Skills, and Items with their artwork and game data |
| Account | `/users/...` | Sign-in, registration, recovery, confirmation, and settings |

### Training controls

- Roster tabs switch heroes instantly with preloaded targets. Use **1–3** to switch heroes, **Q/W/E/R** to level skills, **F** to open or close the Shop, and **Left/Right** and **Space** to select and start a target battle.
- In battle, **Space** attacks or continues from the result. **T** and **G** toggle automation where available.
- Guest onboarding uses contextual arrows rather than tutorial screens. The first battles guide the player through all three hero tabs, and the finish flow points the player back to Base and registration.

### Collection and Arena presentation

- Selecting an avatar in Base opens its completed runs and skins, or its unlock showcase. Unlock controls pair the cost with the available balance and show the league prerequisite when needed. Old Tavern links redirect to Base. Avatar-specific links open the corresponding skin gallery.
- Arena's 3v3 leaderboard shows daily wins and bracket movement. The 1v1 leaderboard sorts by Arena Rating. Season Score is shown separately in profile and Community.
- Completed manual and automated matches use the same summary. Battles can be opened individually, and fallen heroes are dimmed so their builds remain visible.
- Public hero pages show builds and results. Only the owner can open **Customize hero** or see training milestones.

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
| Team training | `lib/moba/game/team_training.ex`, `lib/moba/game/team_runs.ex`, `lib/moba/game/training_encounters.ex` |
| Arena and Match rules | `lib/moba/game/arena.ex`, `lib/moba/game/matches.ex`, `lib/moba/game/season_score.ex` |

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
| `@base_hero_count` | 6 | Default list limit in game code, separate from the 10 starter avatars |
| `@turn_mp_regen_multiplier` | 0.02 | MP regen per turn (2%) |
| `@shard_buyback_minimum` | 5 | Min shards for buyback |

### PvE
| Constant | Value | Description |
|----------|-------|-------------|
| `@total_pve_turns` | 25 | Reserve turns at Adept and above |
| `@turns_per_tier` | 5 | Turns per league tier |
| `@base_xp` | 600 | XP for level 2 |
| `@xp_increment` | 50 | Additional XP per level |
| `@initial_gold` | 1,200 | Starting gold (tier 0) |
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
| `@daily_match_limit` | 20 | Daily 3v3 match limit and size of the separate shared reward allowance |
| `@matchmaking_shards` | 30 | Shards per eligible Arena game |
| `@duel_timer_in_seconds` | 60 | Pick timeout |
| `@turn_timer_in_seconds` | 30 | Battle turn timeout |
| `@immortal_streak_multiplier` | 0.01 | 1% stat penalty per streak |
| `@daily_ranking_limit` | 50 | Daily leaderboard size |
| `@season_ranking_limit` | 50 | Season leaderboard size |
| `@maximum_points_difference` | 200 | Rating gap cutoff for duel wins, losses, and live draws |
| `@minimum_duel_points` | 2 | Minimum used in the favorite-win and draw calculations |
| `@available_hero_days` | 30 | Days before hero public |

---

## Appendix B: Avatar Reference

24 playable avatars with role distribution (Boss excluded):

| Role | Avatars |
|------|---------|
| Tank | Abaddon, Doom, Dragon Knight |
| Bruiser | Axe, Bloodseeker, Sven, Tusk |
| Carry | Anti-Mage, Juggernaut, Phantom Assassin, Sniper, Templar Assassin, Terrorblade, Troll Warlord, Weaver |
| Nuker | Leshrac, Lina, Puck, Pugna, Rubick, Techies, Tinker |
| Support | Dazzle, Omniknight |
