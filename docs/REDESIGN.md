# REDESIGN.md — Frontend Rebuild with WC3UI

## Overview

Rebuild the entire frontend under a `/v2` scope using modern Phoenix LiveView patterns and the [WC3UI component library](https://wc3ui.banteg.xyz/). The existing frontend stays untouched and live while v2 is built screen by screen. Once v2 reaches feature parity, the old frontend is removed and v2 becomes the default.

### Why

The current frontend was built on LiveView 0.1 patterns:
- 70 underscore partials rendered via `render/2`
- 18 View modules generating HTML with `content_tag`
- 3 layout-level LiveViews (sidebar, current_hero, current_player) as separate processes
- Webpack + Bootstrap 4 + jQuery + SCSS
- No function components, no `core_components.ex`
- `push_redirect` instead of `push_navigate`, `Routes.live_path` instead of verified routes
- `raw/1` for HTML injection, `PhoenixHTMLHelpers` shim dependency

None of this can be incrementally fixed without touching every file. A parallel rebuild under `/v2` lets us adopt modern patterns cleanly while keeping the game live.

### Approach

**Dual-scope architecture.** Both v1 and v2 share the same backend (`Moba.Game`, `Moba.Engine`, `Moba.Accounts`) and the same database. They run in the same Phoenix application with separate asset pipelines and layouts. Users on v1 see no changes. V2 is built and tested behind `/v2` routes until ready.

### Relationship to MIGRATION.md

`MIGRATION.md` describes future **gameplay** changes (V1.5 roguelite training, consumables, arena leagues). This redesign is **purely a frontend rebuild on current V1 gameplay**. The two are independent workstreams:

1. Land the redesign first — v2 frontend with current game mechanics
2. Implement V1.5 gameplay changes on the v2 frontend later

**Agents working on this redesign should ignore `MIGRATION.md`.** Build v2 to match what v1 currently does, not what V1.5 will do.

---

## Current State (V1)

### Tech Stack

| Dependency | Current Version | Target (V2) |
|------------|----------------|-------------|
| Elixir | 1.16 | 1.16 (no change) |
| Phoenix | 1.7.12 | 1.7.12 (no change) |
| Phoenix LiveView | 0.20.14 | 1.x (latest stable) |
| Phoenix HTML | 4.1 | 4.1 (no change) |
| Phoenix View | 2.0 | Remove (not needed in v2) |
| PhoenixHTMLHelpers | 1.0 | Remove (not needed in v2) |
| Webpack | 5.68 | Remove (v2 uses esbuild) |
| Bootstrap | 4.3.1 | Remove (v2 uses WC3UI) |
| jQuery | 3.5.1 | Remove (v2 uses vanilla JS) |

### V1 File Inventory

**LiveViews** (15 modules in `lib/moba_web/live/`):
- `training_live.ex` — Training flow (targets, battles, farming, boss, death)
- `battle_live.ex` — Turn-by-turn battle viewer with skill selection
- `battles_live.ex` — Battle history list
- `dashboard_live.ex` — Main hub: hero list, PvE progression, quests
- `create_live.ex` — Hero creation: avatar selection, skill picking
- `arena_live/index.ex` — Arena: rankings, matchmaking, duel list
- `arena_live/edit.ex` — Team management: add/remove heroes, reorder
- `duel_live.ex` — Real-time duel: pick phases, timer, battle execution
- `match_live.ex` — 5v5 match viewer
- `hero_live.ex` — Individual hero detail page
- `player_live.ex` — Player profile page
- `community_live.ex` — Community: rankings, message board
- `tavern_live.ex` — Unlock shop: avatars, skills, skins
- `library_live.ex` — Game library: browse all avatars, skills, items
- `sidebar_live.ex` — Navigation sidebar (layout-level, replaced by hook in v2)
- `current_hero_live.ex` — Hero stats panel + shop (layout-level, replaced by hook in v2)
- `current_player_live.ex` — Player info (layout-level, replaced by hook in v2)

**LiveComponents** (2 modules in `lib/moba_web/live/components/`):
- `shop_component.ex` — Item shop (buy/sell/transmute)
- `tutorial_component.ex` — Tutorial overlay (Shepherd.js-based)

**View Modules** (18 modules in `lib/moba_web/views/`):
- `training_view.ex`, `battle_view.ex`, `arena_view.ex`, `create_view.ex`, `dashboard_view.ex`, `duel_view.ex`, `hero_view.ex`, `match_view.ex`, `player_view.ex`, `community_view.ex`, `tavern_view.ex`, `library_view.ex`, `shop_view.ex`, `current_hero_view.ex`, `layout_view.ex`, `game_view.ex`, `error_view.ex`, `error_helpers.ex`

**Partial Templates** (70 files in `lib/moba_web/templates/`):
- `training/` — 9 partials: `_boss`, `_dead`, `_farm_tabs`, `_gank`, `_header`, `_meditation`, `_mine`, `_pending_battle`, `_target`
- `battle/` — 15 partials: `_active_battle`, `_active_turn`, `_battle_row`, `_description`, `_duel_rewards`, `_effects`, `_first_description`, `_hero`, `_league_rewards`, `_loser_league_step`, `_match_rewards`, `_passive_turn`, `_pve_rewards`, `_turn`, `_turn_hero`, `_turn_timer`, `_winner_league_step`
- `arena/` — 8 partials: `_duel_battle`, `_duel_row`, `_duels`, `_hero`, `_matchmaking`, `_pvp_progression`, `_ranking`, `_team_hero`
- `dashboard/` — 4 partials: `_hero`, `_hero_list`, `_pve_progression`, `_pve_tier_rewards`
- `create/` — 5 partials: `_avatar_selection`, `_background_avatar`, `_build`, `_item`, `_stats`
- `duel/` — 4 partials: `_battle_review`, `_eligible_hero`, `_picked_hero`, `_turn_hero`
- `match/` — 5 partials: `_battle_review`, `_hero`, `_picked_hero`, `_team`, `_turn_hero`
- `hero/` — 3 partials: `_finished_hero`, `_quest`, `_stats`
- `current_hero/` — 1 partial: `_stats`
- `community/` — 2 partials: `_hero`, `_player`
- `player/` — 3 partials: `_duels`, `_hero`, `_matches`
- `shop/` — 2 partials: `_actions`, `_item`
- `tavern/` — 4 partials: `_actions`, `_avatar`, `_featured_avatar`, `_skill`
- `layout/` — 3 partials: `_guest_navigation`, `_head`, `_mobile_navigation`

**JS Hooks** (`assets/js/hooks.js`):
- Uses jQuery throughout
- Global `interval` variable for timers
- `sweetalert` for dialogs
- `document.execCommand('copy')` (deprecated)
- Mix of modern (`this.el`, `this.pushEvent`) and legacy patterns

**Shared Helper** (`lib/moba_web/game_helpers.ex`):
- HTML generation with `content_tag` and `raw/1`
- Imported by multiple View modules

### Screen Descriptions

What each v1 screen does. Agents porting to v2 must replicate this behavior.

**Dashboard** (`/dashboard`)
- Shows list of player's heroes (finished and in-training)
- PvE tier progression display (current tier, next tier requirements)
- Quest/reward display for tier advancement
- Entry point after login — main hub

**Create** (`/create`)
- Step 1: Choose avatar from available pool (filtered by unlocks)
- Step 2: Choose 3 skills from available pool (ultimate auto-assigned)
- Step 3: Confirm and create hero
- Redirects to training after creation

**Training** (`/training`)
- Shows current hero state: level, HP/MP, gold, skills, items
- Displays 6-9 battle targets (with difficulty labels)
- Actions: Battle a target, Meditate (passive XP), Mine (passive gold)
- Pending battle state: skill selection before fight starts
- League progression: step challenges at certain levels
- Boss fight: Roshan at Master league
- Death state: buyback options (gold or shard)
- Farm tabs: switch between battle/meditate/mine views
- Redirect to battle when fight starts

**Battle** (`/battle/:id`)
- Turn-by-turn battle display
- Each turn shows: attacker, defender, skill used, damage, effects
- For manual battles: skill selection interface
- For auto battles: watch turns play out
- Battle result: rewards (XP, gold, league advancement)
- Navigation to next battle or back to training

**Arena** (`/arena`)
- Rankings display (daily and season)
- Matchmaking: find opponent, initiate match or duel
- Duel list: recent and active duels
- Team management link
- PvP progression display (bracket, points)

**Arena Edit** (`/arena/edit`)
- Manage teams of 5 heroes
- Add heroes from own roster or top 100 public heroes
- Reorder heroes within team
- Name teams, mark as defensive/offensive
- Multiple teams allowed

**Duel** (`/duel/:id`)
- Real-time 1v1 duel with pick phases
- Phase sequence: player_first_pick → opponent_first_pick → battle → opponent_second_pick → player_second_pick → battle → finished
- 60-second pick timer (auto-pick on timeout)
- Hero selection from player's roster
- Battle viewer for each phase
- Results and point changes

**Match** (`/match/:id`)
- 5v5 match viewer
- Sequential 1v1 battles between teams
- Winner stays and fights next opponent
- Match result with point changes
- Battle review for each individual fight

**Hero** (`/hero/:id`)
- Individual hero stats page
- Skills with levels, items equipped
- Battle history for this hero
- Quest progress (for current training hero)

**Player** (`/player/:id`)
- Player profile: name, PvP tier, points
- Hero collection (best hero per avatar)
- Recent duels and matches

**Community** (`/community`)
- Player rankings (season and daily)
- Hero rankings (PvE, by total farm)
- Message board (simple text messages)

**Tavern** (`/tavern`)
- Unlock shop using shards
- Avatar unlocks: 150 shards each
- Skill unlocks: 100 shards each
- Skin unlocks: 500 or 1000 shards
- Shows locked/unlocked state for each

**Library** (`/library`)
- Browse all avatars, skills, items in the game
- Read-only reference — no interactions
- Useful for build planning

### Backend API Surface

V2 LiveViews call the same backend contexts as v1. Key public functions by domain:

**`Moba.Game`** (gameplay orchestrator — `lib/moba/game.ex`):
- Heroes: `create_hero!/3`, `get_hero!/1`, `prepare_hero_for_pvp!/1`, `finish_hero!/1`
- Training: `start_pve_battle!/2`, `finish_pve_battle!/1`, `start_farming!/3`, `finish_farming!/1`
- Targets: `list_targets/1`, `generate_targets!/1`, `refresh_targets!/1`
- Skills: `level_skill!/2`, `can_level_skill?/2`
- Items: `buy_item!/2`, `sell_item!/2`, `transmute_item!/2`
- Leagues: `start_league_battle!/1`, `finish_league_battle!/1`
- Arena: `create_match!/2`, `create_duel!/2`
- Duels: `pick_duel_hero!/3`, `auto_pick_duel_hero!/1`, `next_duel_phase!/1`
- Players: `get_player!/1`, `update_player!/2`
- Teams: `create_team!/2`, `update_team!/2`, `delete_team!/1`

**`Moba.Engine`** (battle orchestrator — `lib/moba/engine.ex`):
- `create_pve_battle!/2` — Create PvE training battle
- `create_league_battle!/2` — Create league challenge battle
- `create_pvp_battle!/2` — Create PvP battle (match/duel)
- `next_turn!/1` — Process next battle turn
- `auto_finish_battle!/1` — Run battle to completion

**`Moba.Accounts`** (user management — `lib/moba/accounts.ex`):
- `get_user!/1`, `update_user!/2`
- `unlock!/3` — Unlock avatar/skill/skin with shards
- `create_message!/2`, `list_messages/0` — Community messages
- `shard_buyback!/1` — Shard buyback for training death

**PubSub Topics** (subscribe in `on_mount` hook or LiveView mount):
- `"player:#{player_id}"` — Player updates (points, tier changes)
- `"hero:#{hero_id}"` — Hero updates (level, items, training state)
- `"battle-#{battle_id}"` — Battle turn updates (real-time battles)
- `"duel-#{duel_id}"` — Duel phase updates (picks, timer)
- `"community"` — Community message board updates

---

## Testing Strategy

**Do NOT write tests for v1 LiveViews.** The v1 frontend is being replaced, not refactored. V1 tests would assert against HTML that no longer exists in v2.

**Do NOT write additional backend/context tests.** The backend has been stable for years. `Game`, `Engine`, and `Accounts` are already tested in `test/moba/`.

**Write v2 LiveView tests as you build each screen.** Each phase should produce tests alongside the LiveViews. Test:
- **Mount and render** — page loads, shows expected content
- **Events** — every `phx-click`, `phx-submit`, `phx-change` triggers correct behavior
- **State transitions** — conditional renders (alive/dead, boss/normal, duel phases)
- **Navigation** — redirects go to correct pages
- **PubSub** — broadcasting updates re-renders affected components
- **Edge cases** — empty states, no heroes, no gold, expired timer

Test files go in `test/moba_web/v2/live/` mirroring the v2 LiveView structure.

---

## Architecture

### Directory Structure

```
lib/moba_web/
├── live/                              # V1 (untouched)
├── templates/                         # V1 (untouched)
├── views/                             # V1 (untouched)
│
├── v2/
│   ├── hooks/
│   │   ├── require_auth.ex            # on_mount: redirects if not logged in
│   │   └── load_game_state.ex         # on_mount: loads player + hero, subscribes PubSub
│   │
│   ├── components/
│   │   ├── core_components.ex         # WC3UI wrappers (buttons, inputs, panels, dialogs)
│   │   ├── layout_components.ex       # sidebar, hero_panel, nav, chrome
│   │   ├── game_components.ex         # hero_card, skill_icon, item_slot, stat_bar
│   │   └── battle_components.ex       # turn_display, effect_list, skill_selector
│   │
│   ├── layouts/
│   │   ├── root.html.heex            # HTML shell, loads v2 assets
│   │   └── app.html.heex             # game chrome (sidebar, hero panel, content area)
│   │
│   └── live/
│       ├── dashboard_live.ex
│       ├── dashboard_live.html.heex   # co-located template
│       ├── training_live.ex
│       ├── training_live.html.heex
│       ├── battle_live.ex
│       ├── battle_live.html.heex
│       ├── create_live.ex
│       ├── create_live.html.heex
│       ├── arena_live.ex
│       ├── arena_live.html.heex
│       ├── duel_live.ex
│       ├── duel_live.html.heex
│       ├── tavern_live.ex
│       ├── tavern_live.html.heex
│       ├── hero_live.ex
│       ├── hero_live.html.heex
│       ├── community_live.ex
│       ├── community_live.html.heex
│       ├── player_live.ex
│       ├── player_live.html.heex
│       ├── library_live.ex
│       └── library_live.html.heex
│
assets_v2/
├── package.json                       # WC3UI + minimal deps
├── js/
│   ├── app.js                         # LiveView socket + hooks
│   └── hooks/                         # vanilla JS hooks (no jQuery)
├── css/
│   └── app.css                        # WC3UI imports + custom styles
└── vendor/                            # WC3UI assets if needed
```

### Router

```elixir
# Existing v1 routes stay untouched
live_session :default, on_mount: MobaWeb.PlayerLiveAuth do
  # ... all existing routes
end

# V2 routes — separate live_session, separate layout, separate hooks
live_session :v2_game,
  on_mount: [
    MobaWeb.V2.Hooks.RequireAuth,
    MobaWeb.V2.Hooks.LoadGameState
  ],
  layout: {MobaWeb.V2.Layouts, :app},
  root_layout: {MobaWeb.V2.Layouts, :root} do

  scope "/v2", MobaWeb.V2 do
    pipe_through [:browser]

    live "/", DashboardLive
    live "/training", TrainingLive
    live "/battle/:id", BattleLive
    live "/create", CreateLive
    live "/arena", ArenaLive
    live "/duel/:id", DuelLive
    live "/tavern", TavernLive
    live "/hero/:id", HeroLive
    live "/community", CommunityLive
    live "/player/:id", PlayerLive
    live "/library", LibraryLive
  end
end
```

### Asset Pipeline

V2 has a completely independent asset pipeline. **Bootstrap, jQuery, and the existing Webpack config are irrelevant to v2** — they are never loaded by the v2 layout. The two pipelines coexist without conflict because each root layout loads only its own bundle.

| Aspect | V1 (untouched) | V2 (new) |
|--------|----------------|----------|
| Bundler | Webpack 5 | esbuild (Phoenix default) |
| CSS | SCSS + Bootstrap 4 | WC3UI + CSS custom properties |
| JS | jQuery + SweetAlert + Tippy | Vanilla JS + WC3UI JS |
| Output path | `priv/static/js/app.js` | `priv/static/v2/js/app.js` |
| Layout loads | `<script src="/js/app.js">` | `<script src="/v2/js/app.js">` |
| Dependencies | `assets/package.json` | `assets_v2/package.json` |

**How the dual setup works in practice:**

1. V1 Webpack continues running via `assets/webpack.config.js` → outputs to `priv/static/js/` and `priv/static/css/`
2. V2 esbuild runs via a new config in `config/config.exs` → outputs to `priv/static/v2/js/` and `priv/static/v2/css/`
3. V1 `root.html.heex` loads `<script src={~p"/js/app.js"}>` + `<link href={~p"/css/app.css"}>`
4. V2 `root.html.heex` loads `<script src={~p"/v2/js/app.js"}>` + `<link href={~p"/v2/css/app.css"}>`
5. Phoenix serves both from `priv/static/` via `Plug.Static`

The esbuild config for v2 in `config/config.exs`:

```elixir
config :esbuild,
  v2: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/v2/js
      --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets_v2", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```

**There is no Bootstrap contamination in v2.** The v2 layout never loads Bootstrap CSS. The v2 JS bundle never includes jQuery. WC3UI replaces all of it. During Phase 9 (cutover), the v1 pipeline is deleted entirely.

---

## Key Pattern Changes

### Shared LiveViews → on_mount Hooks + Function Components

**V1:** Three separate LiveView processes mounted in the layout via `live_render`:
- `SidebarLive` — navigation
- `CurrentHeroLive` — hero stats + shop
- `CurrentPlayerLive` — player info

Each is a separate Erlang process per user session. They communicate via PubSub, leading to sync issues and complexity.

**V2:** One `on_mount` hook loads shared data into assigns. Layout uses function components. One process per page.

```elixir
# lib/moba_web/v2/hooks/load_game_state.ex
defmodule MobaWeb.V2.Hooks.LoadGameState do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    player = load_player_from_session(session)
    hero = player && load_current_hero(player)

    socket =
      socket
      |> assign(current_player: player, current_hero: hero)
      |> maybe_subscribe(player)

    {:cont, socket}
  end

  defp maybe_subscribe(socket, nil), do: socket
  defp maybe_subscribe(socket, player) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Moba.PubSub, "player:#{player.id}")
    end
    socket
  end
end
```

```elixir
# lib/moba_web/v2/layouts/app.html.heex
<.sidebar current_player={@current_player} current_hero={@current_hero} />
<.hero_panel hero={@current_hero} />
<main>
  {@inner_content}
</main>
```

Every LiveView in the `v2_game` session automatically gets `@current_player` and `@current_hero`. PubSub updates are handled in the page LiveView's `handle_info`, and function components re-render automatically because assigns changed. No separate processes, no sync bugs.

### Partials → Function Components

**V1:**
```elixir
<%= render("_target.html", target: target, hero: @current_hero) %>
<%= TrainingView.render("_header.html", Map.merge(assigns, %{origin: "battles"})) %>
```

**V2:**
```elixir
<.target target={target} hero={@current_hero} />
<.training_header origin="battles" hero={@current_hero} />
```

All 70 partials become function components in domain-specific modules (`game_components.ex`, `battle_components.ex`, etc.). View modules are eliminated entirely.

### View Helpers → Component Attrs or Private Functions

**V1:** View modules contain helper functions that generate HTML with `content_tag` and `raw/1`.

**V2:** Display logic goes into:
- **Component attrs** for simple transformations (formatting, class selection)
- **Private helper functions** inside the component module
- **No `content_tag`, no `raw/1`** — everything is HEEx

### Navigation

**V1:**
```elixir
push_redirect(socket, to: Routes.live_path(socket, MobaWeb.BattleLive, id))
```

**V2:**
```elixir
push_navigate(socket, to: ~p"/v2/battle/#{id}")
```

### Render Delegation → Co-located Templates

**V1:**
```elixir
def render(assigns) do
  MobaWeb.TrainingView.render("index.html", assigns)
end
```

**V2:** No `render/1` function needed. LiveView auto-discovers `training_live.html.heex` next to `training_live.ex`.

### jQuery Hooks → Vanilla JS Hooks

**V1:**
```javascript
mounted() {
  $(".tooltip").tippy({...});
  $(".element").fadeIn();
}
```

**V2:**
```javascript
mounted() {
  this.el.querySelectorAll("[data-tooltip]").forEach(el => {
    // WC3UI tooltip or native approach
  });
}
```

All hooks use `this.el` scoping and vanilla JS. No jQuery, no global state.

---

## Modern LiveView Features to Adopt

These features are available in LiveView 0.20+ (current) and 1.0+ (upgrade target).

### assign_async — Non-blocking Data Loading

Load data without blocking mount. Users see the page immediately with loading states.

```elixir
def mount(%{"id" => id}, _session, socket) do
  {:ok,
    socket
    |> assign_async(:hero, fn -> {:ok, %{hero: Game.get_hero!(id)}} end)
    |> assign_async(:targets, fn -> {:ok, %{targets: Game.list_targets(id)}} end)}
end
```

```elixir
<.async_result :let={hero} assign={@hero}>
  <:loading><.hero_skeleton /></:loading>
  <:failed>Something went wrong</:failed>
  <.hero_panel hero={hero} />
</.async_result>
```

**Use for:** Dashboard hero collection, Arena opponent lists, Community rankings, any mount that queries the database.

### Streams — Memory-Efficient Lists

Send list items to the client and free them from server memory. Insert/delete items without re-sending the whole list.

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :heroes, Game.list_heroes(player))}
end

def handle_info({:hero_finished, hero}, socket) do
  {:noreply, stream_insert(socket, :heroes, hero)}
end
```

```elixir
<div id="heroes" phx-update="stream">
  <.hero_card :for={{dom_id, hero} <- @streams.heroes} id={dom_id} hero={hero} />
</div>
```

**Use for:** Hero lists (dashboard), player rankings (community), battle history, duel history.

### render_with — Skeleton Screens

Show a lightweight skeleton on disconnected render (first paint), full content after WebSocket connects.

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    {:ok, load_full_data(socket)}
  else
    {:ok, render_with(socket, &loading_skeleton/1)}
  end
end
```

**Use for:** Complex pages like Dashboard, Arena, Training.

### attach_hook — Event Delegation

Extract groups of related events from a LiveView into separate modules. Keeps LiveViews focused.

```elixir
def mount(_params, _session, socket) do
  {:ok,
    socket
    |> attach_hook(:shop, :handle_event, &ShopEvents.handle/3)
    |> attach_hook(:consumables, :handle_event, &ConsumableEvents.handle/3)}
end
```

**Use for:** Training (battle events, farming events, shop events), Arena (matchmaking, duel events), any LiveView with 10+ handle_event clauses.

### push_event with dispatch: :before

Fire JS events before DOM patching. Useful for sound effects and animations.

```elixir
{:noreply,
  socket
  |> push_event("play-sound", %{sound: "battle-start"}, dispatch: :before)
  |> assign(battle: battle)}
```

**Use for:** Battle start/end sounds, level up effects, skill cast animations.

### static_changed? — Deploy Notifications

Notify users when a new version is deployed so they can reload.

```elixir
# In on_mount hook
{:cont, assign(socket, static_changed?: static_changed?(socket))}
```

---

## WC3UI Integration

**Website:** https://wc3ui.banteg.xyz/

**What it is:** A themeable, accessible component library inspired by the Warcraft III interface. Ships with four faction themes (Human, Orc, Night Elf, Undead). Framework-agnostic — works with React, Vue, Svelte, and vanilla JS. 1.2kb core, zero dependencies, tree-shakeable ESM.

**Why it fits this game:** BrowserMOBA is a DotA/WC3-inspired game. WC3UI provides authentic Warcraft III chrome — gold-trimmed buttons, stone textures, faction-themed panels, ability buttons with cooldown states, resource counters, health/mana bars, command card grids, and hero portrait frames. This replaces Bootstrap 4 (generic web framework CSS) with a purpose-built gaming UI.

### Installation

```bash
cd assets_v2 && npm install wc3ui
```

Import in `app.js` and `app.css`. Use component markup directly in HEEx templates.

### Compatibility with LiveView

WC3UI uses CSS custom properties and standard HTML elements. LiveView's DOM patching works with standard elements. Key validation points during spike:

1. **DOM patching** — Verify LiveView morphdom correctly patches WC3UI-styled elements
2. **Shadow DOM** — If any WC3UI components use Shadow DOM, verify LiveView events bubble correctly
3. **CSS custom properties** — Verify faction theme switching works with LiveView re-renders
4. **Form elements** — Verify WC3UI dropdowns, sliders, checkboxes work with `phx-change`/`phx-submit`

### WC3UI Component Reference

Full catalog of available components from https://wc3ui.banteg.xyz/. Grouped by category.

#### Buttons

| Component | Description | States |
|-----------|-------------|--------|
| **FactionTab** | Race selector tabs. Text turns gold on hover/active. | Normal, Active, Disabled |
| **Options Menu Button** | Race-themed buttons with unique background/border/hover textures per faction. | Normal, Disabled |
| **Main Menu Button** | Primary action button inside a decorative border frame. Used for major actions. | Normal, Disabled |
| **Dialog Button** | Standalone confirm button with narrower frame. For single-action dialogs. | Normal, Disabled |
| **Button Border Variants** | Decorative border frames in several sizes: Border, BorderSingle, Large, LargeSingle, Small, SmallSingle, Tiny. | Various sizes |
| **Login Screen Button** | Tiled stone background with gold border and hover glow. | Normal, Disabled |
| **Bordered Button** | Heavier decorative edge, same stone backdrop. | Normal, Disabled |
| **Small Button** | Compact button for secondary actions. | Normal, Disabled |
| **Campaign Button** | Unique backdrop and border textures. | Normal, Disabled |
| **Ability Button** | **In-game command card grid buttons with pressed, disabled, and cooldown states.** | Interactive, Active, Pressed, Disabled, Cooldown, No Resources |

#### Controls (Forms)

| Component | Description | States |
|-----------|-------------|--------|
| **Dropdown** | Pull-down selector with dedicated arrow. For option menus and popup lists. | Interactive, Disabled |
| **Slider** | Options menu slider with shared track and race-specific thumb. | Interactive (value%), Disabled |
| **Checkbox** | In-game option toggle. Pressed background is race-specific, check mark shared. | Interactive, Checked, Unchecked, Disabled Checked, Disabled |
| **Radio Button** | Mutually exclusive selector. Selected dot glows over stone background. | Interactive Group, Selected, Unselected, Disabled Selected, Disabled |
| **Text Input** | Two styles: decorated race-themed variant for in-game menus, and plain Battle.net variant for login screens. | Normal, Disabled |
| **Scrollbar** | Vertical scroll track with up/down arrows and draggable knob. | Interactive, Disabled |
| **Text Area** | Scrollable text panel with decorated border and attached scroll thumb. | Interactive |
| **List Box** | Bordered scrollable list pairing text input container with scrollbar. | Selectable Items |

#### Data Display

| Component | Description | Notes |
|-----------|-------------|-------|
| **ResourceCounter** | **Animated numeric display with icon slot. Ticks up smoothly like gold flowing into treasury.** Supports Gold, Lumber, Supply, Upkeep. | Animated transitions |
| **CommandCard** | **Spatial action grid with hotkey hints, cooldown states, and empty-slot affordances.** Matches the WC3 in-game command card layout. | Grid layout with hotkeys |
| **UnitQueue** | **Task queue with progress indicator and cancelable pending slots.** For build pipelines, agent workflows, or anything that trains. | Progress + cancel |
| **Tooltip** | **Rich content tooltips with title, description, hotkey badge, and inline resource costs.** Example: "Build Footman (F) — Basic frontline infantry. 135g 0mp 2supply" | Title, desc, hotkey, costs |
| **PortraitFrame** | **Hero-tier avatar frame with live 3D portrait rendering.** | Frame + portrait |

#### Bars

| Component | Description | Example |
|-----------|-------------|---------|
| **HealthBar** | Green unit health bar from in-game portrait panel with highlight and edge overlays. | `637 / 650` |
| **ManaBar** | Blue mana bar sharing same highlight and edge overlays as health bar. | `276 / 300` |
| **XPBar** | Hero experience bar with purple fill and classic XP border frame. | `Level 3 · 9%` |
| **Progress Bar** | Generic timed progress indicator for training, upgrades, queued actions. | `42%` |
| **Build Progress** | Construction progress indicator with its own fill and border textures. | `76%` |
| **Loading Screen Bar** | Full-width loading bar from map load screen with tiled track, glass border, and progress glow. | `62%` |

#### Border Textures

8 border BLP textures across 2 categories. 9-slice atlases, bar borders, and panel borders.

| Category | Description |
|----------|-------------|
| **Menu** | Race-specific nine-slice panel and button borders from the options menu. Per-faction. |
| **Cinematic** | Letterbox borders for in-game cinematics. Per-faction. |

#### Design Tokens

60+ design tokens per faction. All overridable via CSS custom properties.

| Token | Human | Orc | Night Elf | Undead |
|-------|-------|-----|-----------|--------|
| Background | `#2A2A3A` | `#2A1F1A` | `#1A2A2A` | `#1A1A2A` |
| Text | `#ECEFF7` | `#F0E0C0` | `#D0E8E0` | `#C8C0D0` |
| Accent | `#4A7ABF` | `#BF4A4A` | `#4ABFAA` | `#6A4ABF` |
| Glow | `#6DB3F2` | `#FF6644` | `#44FFCC` | `#8866FF` |

#### Accessibility

All components meet WCAG 2.1 AA contrast ratios (including Undead theme). Built-in:
- Keyboard navigation
- ARIA labels
- Reduced motion support
- Color contrast AA
- Focus-visible rings (faction-styled)

#### Bundle Size

Tree-shakeable ESM. Import only what you need. Average component weighs under 1.4kb gzipped.

| Component | Size |
|-----------|------|
| GoldButton | 1.2kb |
| ResourceCounter | 0.8kb |
| CommandCard | 1.9kb |
| Tooltip | 1.4kb |
| PortraitFrame | 1.1kb |
| HealthBar | 0.6kb |
| Minimap | 2.1kb |
| Dialog | 1.7kb |
| ChatBubble | 0.9kb |
| HeroCard | 2.4kb |

Works with Tailwind (uses CSS custom properties internally, Tailwind utility classes compose alongside faction themes).

### Faction Theme Strategy

WC3UI ships with 4 themes: Human, Orc, Night Elf, Undead. One prop/attribute changes everything — all components adapt to the chosen faction.

**Recommended approach:** Player-selectable theme stored on User schema.

```elixir
# User schema
field :ui_theme, :string, default: "human"
```

```elixir
# Root layout
<body data-faction={@current_player && @current_player.user.ui_theme || "human"}>
```

Alternative: Map themes to avatar roles (Tanks→Undead, Carries→Orc, etc.). Decide during Phase 0 spike.

### Component Mapping to BrowserMOBA

How WC3UI components replace current Bootstrap/custom elements:

| Current (Bootstrap/custom) | WC3UI Replacement |
|----------------------------|-------------------|
| `.btn .btn-primary` | Faction-themed button (Options Menu, Main Menu, or Dialog variant) |
| `.form-control` | Text Input (decorated race-themed variant) |
| `<select>` | Dropdown (with dedicated arrow) |
| `.progress` | HealthBar / ProgressBar / XPBar (context-dependent) |
| `.badge` | ResourceCounter (animated) |
| `.tooltip` (Tippy.js) | Tooltip (title, description, hotkey badge, resource costs) |
| `.modal` | Dialog Button + panel borders |
| Custom sidebar | Menu border textures + panels |
| `.nav-tabs` | FactionTab |
| Hero avatar frame | PortraitFrame |
| HP/MP display | HealthBar / ManaBar |

Game-specific mappings that fit particularly well:

| Game Feature | WC3UI Component | Why |
|--------------|-----------------|-----|
| Skill buttons in battle | **AbilityButton** | Has cooldown, pressed, disabled, no-resources states — exactly what skills need |
| Gold/XP display | **ResourceCounter** | Animated tick-up, icon slot — feels like earning gold in WC3 |
| Battle turn queue | **UnitQueue** | Progress indicator + pending slots — maps to sequential battle turns |
| Skill tooltips | **Tooltip** | Title + description + hotkey + resource costs — matches skill info (name, MP cost, cooldown) |
| Training progress | **ProgressBar / BuildProgress** | Training turns as a build bar |
| Loading between battles | **Loading Screen Bar** | Full-width WC3 loading bar |
| Skill selection grid | **CommandCard** | Spatial grid with hotkey hints — the WC3 command card IS the skill panel |
| Hero level / XP | **XPBar** | Purple fill with classic frame |
| Hero portrait | **PortraitFrame** | Avatar image in a hero-tier frame |
| Duel pick timer | **ProgressBar** | Countdown visualization |

---

## Component Inventory

Mapping of current 70 partials to v2 function component modules.

### core_components.ex (WC3UI Wrappers)

Base UI primitives. Thin wrappers around WC3UI elements with LiveView integration.

| Component | Wraps |
|-----------|-------|
| `.button` | WC3UI buttons (all variants) |
| `.input` | WC3UI text input, dropdown, slider, checkbox, radio |
| `.dialog` | WC3UI dialog/modal |
| `.tooltip` | WC3UI tooltip |
| `.panel` | WC3UI bordered panel with faction theme |
| `.progress_bar` | WC3UI progress/health/mana/xp bars |
| `.resource_counter` | WC3UI animated counter |
| `.flash` | Notification flash messages |
| `.form` | Form wrapper with WC3UI styling |
| `.scrollbar` | WC3UI scrollbar for lists |

### layout_components.ex

| Component | Replaces | Source Partials |
|-----------|----------|-----------------|
| `.sidebar` | `SidebarLive` | `layout/_guest_navigation`, `layout/_mobile_navigation`, sidebar logic |
| `.hero_panel` | `CurrentHeroLive` | `current_hero/_stats` |
| `.player_panel` | `CurrentPlayerLive` | player info display |
| `.game_nav` | Navigation links | sidebar navigation |
| `.page_header` | Various headers | `training/_header` |

### game_components.ex

| Component | Replaces | Source Partials |
|-----------|----------|-----------------|
| `.hero_card` | Hero display | `dashboard/_hero`, `community/_hero`, `arena/_hero`, `player/_hero` |
| `.hero_stats` | Stat display | `hero/_stats`, `current_hero/_stats`, `create/_stats` |
| `.skill_icon` | Skill display | Used across many templates |
| `.item_slot` | Item display | `create/_item`, `shop/_item` |
| `.ability_button` | Skill button (WC3UI) | Battle skill selection |
| `.avatar_card` | Avatar display | `create/_avatar_selection`, `create/_background_avatar`, `tavern/_avatar`, `tavern/_featured_avatar` |
| `.hero_list` | Hero grid | `dashboard/_hero_list`, `dashboard/hero_grid` |
| `.quest_card` | Quest display | `hero/_quest` |
| `.pve_progression` | Tier progress | `dashboard/_pve_progression`, `dashboard/_pve_tier_rewards` |
| `.pvp_progression` | PvP progress | `arena/_pvp_progression` |
| `.finished_hero` | Completed hero | `hero/_finished_hero` |
| `.target_card` | Training target | `training/_target` |
| `.shop_item` | Shop item | `shop/_item`, `shop/_actions` |
| `.tavern_skill` | Tavern skill | `tavern/_skill` |
| `.tavern_actions` | Tavern buttons | `tavern/_actions` |

### battle_components.ex

| Component | Replaces | Source Partials |
|-----------|----------|-----------------|
| `.battle_turn` | Turn display | `battle/_turn`, `battle/_active_turn`, `battle/_passive_turn` |
| `.turn_hero` | Hero in turn | `battle/_turn_hero`, `battle/_hero`, `duel/_turn_hero`, `match/_turn_hero` |
| `.effect_list` | Effect display | `battle/_effects` |
| `.battle_description` | Turn text | `battle/_description`, `battle/_first_description` |
| `.battle_row` | Battle in list | `battle/_battle_row` |
| `.active_battle` | Live battle | `battle/_active_battle` |
| `.turn_timer` | Countdown | `battle/_turn_timer` |
| `.battle_rewards` | Result display | `battle/_pve_rewards`, `battle/_league_rewards`, `battle/_duel_rewards`, `battle/_match_rewards` |
| `.league_step` | League result | `battle/_winner_league_step`, `battle/_loser_league_step` |
| `.battle_review` | Post-battle | `duel/_battle_review`, `match/_battle_review` |
| `.picked_hero` | Duel pick | `duel/_picked_hero`, `duel/_eligible_hero`, `match/_picked_hero` |
| `.duel_row` | Duel in list | `arena/_duel_row` |
| `.duel_battle` | Duel battle | `arena/_duel_battle` |
| `.team_hero` | Team member | `arena/_team_hero`, `match/_hero`, `match/_team` |

### training_components.ex (optional, could live in game_components)

| Component | Replaces | Source Partials |
|-----------|----------|-----------------|
| `.training_header` | Header bar | `training/_header` |
| `.training_target` | Target card | `training/_target` |
| `.boss_fight` | Boss display | `training/_boss` |
| `.dead_screen` | Death/buyback | `training/_dead` |
| `.pending_battle` | Battle start | `training/_pending_battle` |
| `.farm_tabs` | Farm options | `training/_farm_tabs` |
| `.gank_display` | Gank view | `training/_gank` |
| `.meditation_view` | Meditation | `training/_meditation` |
| `.mine_view` | Mining | `training/_mine` |

---

## Phase Sequence

### Phase 0: WC3UI Spike (2-3 days)

**Goal:** Validate that WC3UI works with Phoenix LiveView before investing weeks.

**Tasks:**
1. Create `assets_v2/` with esbuild config and WC3UI installed
2. Create minimal v2 layout (`root.html.heex`, `app.html.heex`) loading v2 assets
3. Add `/v2` scope to router with a single LiveView (Dashboard or Library — simplest screens)
4. Build that one screen using WC3UI components: buttons, panels, faction theme
5. Verify: DOM patching works, events fire, theme switching works, no console errors
6. Verify: LiveView hooks work with WC3UI elements (tooltips, etc.)
7. If Shadow DOM issues found, document workarounds or evaluate alternatives

**Exit criteria:** One working screen under `/v2` with WC3UI styling, LiveView events, and no compatibility issues.

**If spike fails:** Evaluate alternatives (custom CSS inspired by WC3 aesthetic, or a different component library). The rest of the plan still applies — only the styling layer changes.

### Phase 1: Foundation (3-4 days)

**Goal:** Set up the v2 infrastructure that all screens will use.

**Tasks:**
1. Create `lib/moba_web/v2/` directory structure
2. Build `core_components.ex` — WC3UI wrappers for button, input, dialog, panel, tooltip, progress bars, resource counters, form, flash
3. Build `require_auth.ex` on_mount hook
4. Build `load_game_state.ex` on_mount hook (loads player + hero, subscribes PubSub)
5. Build `layout_components.ex` — sidebar, hero_panel, game_nav
6. Build v2 layouts (`root.html.heex`, `app.html.heex`) with WC3UI chrome
7. Configure router with `live_session :v2_game`
8. Upgrade LiveView to latest stable (1.x) in `mix.exs`
9. Write tests for on_mount hooks

**Exit criteria:** Navigating to `/v2` shows a working layout with sidebar, hero panel, and WC3UI styling. No content pages yet, just the chrome.

### Phase 2: Static Screens (3-4 days)

**Goal:** Build the simplest screens first to establish component patterns.

**Screens (in order):**
1. **Library** — Read-only, no events. Just displays avatars/skills/items.
2. **Community** — Player/hero rankings. Uses streams for lists.
3. **Player profile** — Display player stats + hero collection.
4. **Hero detail** — Display hero stats, skills, items.

**Tasks per screen:**
1. Create LiveView + co-located template
2. Port `mount` and `handle_params` from v1 (update to modern patterns)
3. Build needed function components in `game_components.ex`
4. Use `assign_async` for data loading, streams for lists
5. Apply WC3UI styling
6. Write LiveView tests (mount, render, navigation)

**Exit criteria:** 4 read-only screens working under `/v2` with full WC3UI styling and tests.

### Phase 3: Dashboard + Hero Creation (4-5 days)

**Goal:** Build the main hub and hero creation flow.

**Screens:**
1. **Dashboard** — Hero list, PvE progression, quest display. Entry point after login.
2. **Create** — Avatar selection, skill picking, hero creation.

**New patterns introduced:**
- Streams for hero lists
- `assign_async` for hero collection loading
- `render_with` skeleton for dashboard first paint
- Form handling for hero creation (avatar + skill selection)
- Event handlers for create flow

**Tasks:**
1. Build `game_components.ex` components: hero_card, hero_list, avatar_card, pve_progression, quest_card
2. Port Dashboard LiveView — mount, events, PubSub handling
3. Port Create LiveView — multi-step creation flow, skill selection, avatar filtering
4. Write tests for all events and render states

**Exit criteria:** User can log in, see dashboard at `/v2`, create a hero, see it in hero list.

### Phase 4: Training (5-7 days)

**Goal:** Build the most complex screen in the game.

**Screen:** Training — target selection, battles, farming, boss fight, death/buyback, leveling.

**New patterns introduced:**
- `attach_hook` for event delegation (battle events, farming events, shop events in separate modules)
- Complex conditional rendering (alive/dead, boss/normal, farming states)
- PubSub for hero updates during training

**Tasks:**
1. Build `training_components.ex`: training_header, target_card, boss_fight, dead_screen, pending_battle, farm_tabs
2. Port Training LiveView — all states (alive, dead, boss, farming)
3. Extract event groups using `attach_hook` delegation
4. Handle all training events: battle, meditate, mine, level_skill, buy_item, sell_item, buyback, refresh_targets
5. Port Shop — either as LiveComponent or as inline panel with event delegation
6. Write tests for every state transition and event

**Exit criteria:** Full training loop works at `/v2` — create hero → train → battle → level → items → boss → finish.

### Phase 5: Battles (4-5 days)

**Goal:** Build the battle viewer and turn-by-turn display.

**Screens:**
1. **Battle** — Turn-by-turn battle viewer with skill selection (for manual battles)
2. **Battles list** — History of recent battles

**New patterns introduced:**
- `push_event` with `dispatch: :before` for battle animations/sounds
- Real-time PubSub for live battle updates (duels)
- Complex turn rendering with effects, descriptions, hero states

**Tasks:**
1. Build `battle_components.ex`: battle_turn, turn_hero, effect_list, battle_description, active_battle, turn_timer, battle_rewards, league_step
2. Port Battle LiveView — all battle types (PvE, league, PvP)
3. Port battle reward displays (PvE rewards, league rewards, duel rewards)
4. Handle skill selection events, next-turn events
5. Write tests for battle rendering and event handling

**Exit criteria:** All battle types render correctly at `/v2`. Manual battles allow skill selection. Battle results show correctly.

### Phase 6: Arena + Duels (5-7 days)

**Goal:** Build the PvP system.

**Screens:**
1. **Arena** — Matchmaking, rankings, team management
2. **Duel** — Real-time pick phases, battle execution

**New patterns introduced:**
- Duel state machine (pick phases, timers)
- Real-time PubSub for live duels
- Team management forms

**Tasks:**
1. Port Arena LiveView — rankings, matchmaking, duel initiation
2. Port Arena Edit (team management) — add/remove heroes, reorder, name teams
3. Port Duel LiveView — full pick/battle state machine with timer
4. Build remaining components: duel_row, duel_battle, team_hero, picked_hero
5. Handle all arena events: create_duel, pick_hero, auto_pick, match initiation
6. Write tests for duel state machine, arena events

**Exit criteria:** Full PvP loop works at `/v2` — team setup → find opponent → duel → pick → battle → results.

### Phase 7: Tavern + Remaining Screens (2-3 days)

**Goal:** Build remaining screens.

**Screens:**
1. **Tavern** — Unlock shop (avatars, skills, skins with shards)
2. **Auth pages** — Login, registration, password reset (if needed under v2)

**Tasks:**
1. Port Tavern LiveView — avatar/skill/skin unlocking
2. Build tavern components: tavern_skill, tavern_actions, featured_avatar
3. Handle unlock events, shard transactions
4. Decide on auth: reuse v1 Pow pages or rebuild under v2
5. Write tests

**Exit criteria:** All game screens functional under `/v2`.

### Phase 8: Polish + Parity Audit (3-5 days)

**Goal:** Ensure v2 is a complete replacement for v1.

**Tasks:**
1. **Feature parity audit** — Walk through every v1 screen, verify v2 has equivalent functionality
2. **Edge case testing** — New accounts, empty states, error states, disconnection/reconnection
3. **Mobile responsiveness** — Verify WC3UI components work on mobile viewports
4. **Performance** — Check socket memory usage, stream efficiency, asset bundle size
5. **Accessibility** — WC3UI claims WCAG 2.1 AA — verify keyboard nav, screen reader labels
6. **JS hooks audit** — Verify all hooks work (timers, clipboard, tutorials, tooltips)
7. **Admin panel** — Decide: keep v1 admin as-is, or build v2 admin (recommend: keep v1)
8. **`static_changed?`** — Add deploy notification banner
9. **Faction theme selector** — Add to user settings if pursuing player-selectable themes

**Exit criteria:** v2 is fully functional, tested, and ready to replace v1.

### Phase 9: Cutover (1-2 days)

**Goal:** Make v2 the default and retire v1.

**Tasks:**
1. Update router: v2 routes become the default (`/`), v1 routes move to `/legacy` or are removed
2. Update root layout to load v2 assets by default
3. Remove v1 scope from router (or keep behind feature flag for rollback)
4. Run full test suite
5. Deploy to staging, full playthrough
6. Deploy to production
7. Monitor for issues, keep v1 code for 1-2 weeks as rollback option

**Post-cutover cleanup (next sprint):**
1. Delete `lib/moba_web/templates/` (all 70 partials)
2. Delete `lib/moba_web/views/` (all 18 View modules)
3. Delete v1 LiveViews replaced by v2
4. Delete `assets/` (Webpack, Bootstrap, jQuery)
5. Remove `phoenix_html_helpers` dependency
6. Move `lib/moba_web/v2/` contents up to `lib/moba_web/`
7. Rename `assets_v2/` to `assets/`
8. Update all route paths (remove `/v2` prefix)
9. Update tests

---

## Timeline Estimate

| Phase | Duration | Cumulative |
|-------|----------|------------|
| 0: WC3UI Spike | 2-3 days | 2-3 days |
| 1: Foundation | 3-4 days | 5-7 days |
| 2: Static Screens | 3-4 days | 8-11 days |
| 3: Dashboard + Create | 4-5 days | 12-16 days |
| 4: Training | 5-7 days | 17-23 days |
| 5: Battles | 4-5 days | 21-28 days |
| 6: Arena + Duels | 5-7 days | 26-35 days |
| 7: Tavern + Remaining | 2-3 days | 28-38 days |
| 8: Polish + Parity | 3-5 days | 31-43 days |
| 9: Cutover | 1-2 days | 32-45 days |

**Total: ~6-9 weeks** (single developer, working full days)

The game stays live and untouched throughout Phases 0-8. Cutover is the only moment of risk, and v1 code remains available for rollback.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| WC3UI Shadow DOM conflicts with LiveView | Blocks entire redesign | Phase 0 spike validates this before any investment |
| WC3UI is unmaintained / breaks | Medium | Library is 1.2kb with zero deps — fork and vendor if needed |
| Training LiveView is more complex than estimated | Schedule slip | Phase 4 has largest buffer; can split into sub-phases |
| Duel real-time sync breaks in v2 | PvP broken | Port v1 PubSub logic directly; test with 2-browser setup |
| Auth (Pow) doesn't work with v2 live_session | Users can't log in | V2 live_session uses same browser pipeline and session; auth is session-based, not LiveView-based |
| Users bookmark /v2 URLs before cutover | Broken links after rename | Add redirects from `/v2/*` to `/*` during cutover |
| Asset bundle too large with WC3UI textures | Slow load | WC3UI is tree-shakeable (1.2kb core); import only what's used |

---

## What This Doc Does NOT Cover

- **V1.5 gameplay changes** — `MIGRATION.md` describes future gameplay changes (roguelite training, consumables, arena leagues). Those are a **separate future workstream** that happens AFTER this redesign lands. **Ignore `MIGRATION.md` when working on this redesign.** Build v2 to match current v1 behavior exactly.
- **Backend changes** — The backend (`lib/moba/`) is stable, fully tested, and shared between v1 and v2. No backend changes are needed for the redesign.
- **Admin panel redesign** — The admin panel (`lib/moba_web/controllers/admin/`) uses Torch-generated controllers. Keep it on v1 as-is. It's internal-only and doesn't need WC3UI.
- **Mobile app** — Out of scope. WC3UI is responsive, so mobile browser should work, but no dedicated mobile work planned.
- **New features** — This is a 1:1 frontend rebuild. No new features, no removed features. Every screen in v2 must do exactly what the v1 screen does.
