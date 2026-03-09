# V2 Component Plan

## Goal

Organize `v2` around clean Phoenix 1.8 component patterns without changing the visual design.

This plan is intentionally conservative:

- Keep the Bootstrap-based UI and current HTML structure where practical.
- Do not redesign the product.
- Do not rewrite working pages for style reasons alone.
- Focus on organization, reuse, and clear ownership.

The desired outcome is:

- LiveViews orchestrate data and events.
- Function components own reusable markup.
- LiveComponents are used only when isolated state is actually needed.
- Repeated hero, battle, layout, and reward UI stops being copied across screens.
- `v2` stops depending on legacy `v1` helpers and “HTML string builder” patterns.

## Non-Goals

- Replacing Bootstrap classes with Tailwind.
- Redesigning page layout or interactions.
- Rewriting all pages in one pass.
- Deleting every legacy helper immediately.

## Constraints

- Keep the UI looking the same.
- Preserve existing routes and behavior.
- Prefer small extractions over large rewrites.
- Match Phoenix 1.8 LiveView conventions.

## Current State

`v2` already has a partial component system:

- `lib/moba_web/v2/components/core_components.ex`
- `lib/moba_web/v2/components/game_components.ex`
- `lib/moba_web/v2/components/layout_components.ex`
- `lib/moba_web/v2/components/hero_bar_components.ex`
- `lib/moba_web/v2/components/pvp_components.ex`
- `lib/moba_web/v2/components/tutorial_component.ex`
- `lib/moba_web/v2/live/components/shop_component.ex`

What is still mixed together:

- Page templates still contain large repeated markup blocks.
- Some component families are split awkwardly between `components/` and `live/`.
- `v2` still uses legacy helpers such as `MobaWeb.GameHelpers`.
- Some helpers return raw HTML strings instead of HEEx/function components.
- Some modules are still “ported v1 markup” rather than a stable `v2` API.

## Progress Update

The component plan is no longer just aspirational. Several core `v2` slices have already been implemented.

### Completed So Far

#### `/start` and `CreateLive`

- `/start` is now a routed `v2` LiveView instead of a controller-mounted `live_render`.
- cache-key setup moved into Plug/session setup instead of a controller wrapper.
- `CreateLive` was split into orchestration plus page-local rendering in:
  - `lib/moba_web/v2/live/create_live.ex`
  - `lib/moba_web/v2/components/create_components.ex`
- the create flow now uses named function components for:
  - avatar picker
  - selected avatar panel
  - build picker
  - custom skill picker
  - selected skills bar
  - create submit panel

#### Shared game display primitives

The following shared display components now exist in `lib/moba_web/v2/components/game_components.ex`:

- `hero_stat_button`
- `hero_stat_group`
- `battle_hero_stat_group`
- `hero_skill_strip`
- `hero_item_strip`
- `skill_image`
- `league_badge`

These are now used across multiple `v2` surfaces instead of duplicated inline markup.

#### Battle turn primitives

A dedicated battle component module now exists:

- `lib/moba_web/v2/components/battle_components.ex`

It currently owns the repeated battle-turn display primitives for:

- battle resource images
- battle status icons
- empty item slots
- resource status badges

These are now used by:

- `battle_live/active_turn.html.heex`
- `battle_live/passive_turn.html.heex`
- `battle_live/turn.html.heex`

This also removed the old raw-HTML `resource_status/2` rendering path from `BattleLive`.

#### Shop rendering primitives

A dedicated shop component module now exists:

- `lib/moba_web/v2/components/shop_components.ex`

It currently owns the repeated shop rendering primitives for:

- shop catalog item cells
- generic shop item images
- inventory item entries
- selected item display
- shop action block
- recipe item display
- transmute result display
- shop empty item slots

These are now used by:

- `lib/moba_web/v2/live/components/shop_component/shop.html.heex`

The `ShopComponent` LiveComponent still owns state and events, but much less of the rendering surface.

#### Hero stat row migration

The shared stat row has already been adopted in:

- `hero_bar_components.ex`
- `hero_live.ex`
- `community_live.ex`
- `pvp_components.ex`
- `battle_live/hero.html.heex` via `battle_hero_stat_group`

#### Skill and item strip migration

Shared skill/item rendering has already been adopted in:

- `hero_live`
- `community_live`
- `pvp_components`
- `player_live`
- `training_live/target.html.heex`
- `training_live/boss.html.heex`
- `battle_live/hero.html.heex`
- `dashboard_live.html.heex`

#### League badge migration

Direct `league-logo` image markup in `v2` was replaced with `league_badge/1` using a legacy-compatible rendering mode.

This has already been adopted in:

- `create_components`
- `player_live`
- `player_live.html.heex`
- `dashboard_live.html.heex`
- `training_live/header.html.heex`
- `battles_live/training_header.html.heex`
- `battle_live/hero.html.heex`
- `pvp_components`

#### Legacy helper cleanup

`v2` no longer depends on `MobaWeb.GameHelpers` from `pvp_components.ex`.

The major `LegacyGH` dependency that remained in shared PvP rendering has been removed.

#### Stat tooltip cleanup

`v2` no longer calls the old `hero_stats_string/2` API directly at page call sites.

Current `v2` stat tooltip usage goes through:

- `hero_stats_tooltip/2` in `lib/moba_web/v2/components/game_helpers.ex`

Current direct `v2` call sites:

- `player_live.ex`
- `training_live/target.html.heex`
- `training_live/boss.html.heex`

#### Library cleanup

`library_live.html.heex` now uses shared skill display primitives instead of hand-rolled skill image markup for:

- avatar ultimate display
- skill grid icons

### What This Means

The project is now past the “prove the pattern” stage.

The `v2` component system already has a functioning base:

- page-local extraction is working (`CreateComponents`)
- shared game primitives are in place
- several of the most duplicated stat/skill/item/league fragments are centralized
- the remaining work is now mostly about finishing adoption and tackling the harder battle/shop surfaces

## Design Principles

### 1. LiveViews should orchestrate, not paint

A LiveView should mainly:

- load data
- assign state
- handle events
- choose which sections/components to render

A LiveView should not own large, repeated UI fragments that are used elsewhere.

### 2. Function components first

Default to function components.

Use LiveComponents only when the component truly needs:

- isolated state
- targeted event handling
- lifecycle separation
- asynchronous local updates

### 3. Preserve markup before improving markup

When extracting UI into a component:

- keep the same classes
- keep the same DOM structure where tests or JS depend on it
- keep the same IDs when already used by tests/hooks

The first refactor is organizational, not aesthetic.

### 4. One component family per concept

Examples:

- hero display belongs in one place
- battle result/reward UI belongs in one place
- layout/nav chrome belongs in one place
- arena/pvp cards belong in one place

If multiple screens render the same concept, they should not each own their own version.

### 5. No new HTML-string UI helpers

Avoid helpers that return raw HTML strings for badges, tooltips, descriptions, or status labels.

Prefer:

- function components
- plain data helpers
- HEEx partial templates via `embed_templates`

## Target Architecture

## Layer 1: Layout Shell

Purpose: app chrome and shared page framing.

Owner modules:

- `lib/moba_web/v2/layouts.ex`
- `lib/moba_web/v2/components/layout_components.ex`

Responsibilities:

- `Layouts.app`
- flash rendering
- sidebar
- mobile nav
- footer stats
- shell-level wrappers such as page containers

Rules:

- No game-specific battle/hero logic here.
- No direct duplication of per-page content.
- Layout components may use Bootstrap classes, but should expose a stable API.

Target subgroups inside `LayoutComponents`:

- shell/navigation
- shell/footer
- shell/page headers
- shell/empty states

## Layer 2: UI Primitives

Purpose: generic reusable components with no MOBA-specific domain knowledge.

Owner module:

- `lib/moba_web/v2/components/core_components.ex`

Responsibilities:

- buttons
- badges
- flash
- panels
- tabs
- bars/counters
- generic modal/container wrappers

Rules:

- These components should not know about heroes, battles, items, or players.
- These should provide Phoenix-friendly interfaces and accept arbitrary classes for Bootstrap preservation.

Planned additions:

- `icon_button`
- `action_button`
- `tooltip_label`
- `section_card`
- `stat_badge`
- `resource_badge`
- `modal_frame`
- `empty_state`
- `loading_button`

These should wrap repeated Bootstrap patterns instead of replacing them visually.

## Layer 3: Game Primitives

Purpose: reusable MOBA-specific components that can appear on many screens.

Owner modules:

- `lib/moba_web/v2/components/game_components.ex`
- `lib/moba_web/v2/components/game_helpers.ex`

Responsibilities:

- hero avatars/portraits
- hero stat rows
- hero summary cards
- skill icons
- item slots
- league badges
- reward badges
- battle effect rows
- progress/status readouts

Rules:

- `GameHelpers` should return data and formatting values, not HTML fragments.
- Any UI currently built with `raw(...)` or interpolated HTML strings should move into function components.

Planned component families:

- `hero_card`
- `hero_meta`
- `hero_stats_row`
- `hero_stats_grid`
- `hero_skills`
- `hero_items`
- `league_badge`
- `reward_list`
- `resource_cost_badge`
- `cooldown_badge`
- `status_badge`

## Layer 4: Domain-Specific Screen Families

Purpose: reusable sections shared by a subset of pages.

These should be split by domain rather than by page.

### Create Flow

Target module:

- `lib/moba_web/v2/components/create_components.ex`

Responsibilities:

- avatar picker grid
- selected avatar hero panel
- build picker
- skill picker
- create CTA area
- guest submit area
- logged-in submit area

Sources to absorb:

- `lib/moba_web/v2/live/create_live.html.heex`
- UI helper functions currently embedded in `lib/moba_web/v2/live/create_live.ex`

### Hero Bar + Shop

Target modules:

- `lib/moba_web/v2/components/hero_bar_components.ex`
- `lib/moba_web/v2/components/shop_components.ex`

Responsibilities:

- top hero bar
- hero resource buttons
- hero build editor area
- shop modal contents
- item buy/sell/transmute panels

Notes:

- The current hero bar may remain function-component based.
- The shop can remain stateful if needed, but its rendering surface should be split into smaller function components.

Status:

- started
- `shop_components.ex` now exists and owns the repeated item/image/action rendering
- `ShopComponent` still owns state/event logic
- further cleanup is still possible, especially around section-level composition and any remaining inline forms

### PvP / Arena

Target module:

- `lib/moba_web/v2/components/pvp_components.ex`

Responsibilities:

- duel cards
- team cards
- player summary rows
- arena ranking entries
- match summary blocks
- turn snapshots

Rules:

- Keep this module on `v2` helpers/components only.
- Do not reintroduce `MobaWeb.GameHelpers`.

### Battle

Target module:

- `lib/moba_web/v2/components/battle_components.ex`

Responsibilities:

- turn header
- battler card
- action/resource badges
- effect list
- reward summaries
- winner/loser step display
- battle log chunks

Sources to absorb:

- `lib/moba_web/v2/live/battle_live/*.heex`
- raw badge/cooldown HTML currently in `lib/moba_web/v2/live/battle_live.ex`

Status:

- started
- shared icon/resource primitives are extracted
- the turn templates now use `BattleComponents`
- larger battle description/effect/reward composition is still in progress

### Community

Target module:

- `lib/moba_web/v2/components/community_components.ex`

Responsibilities:

- feed entries
- update cards
- online player list entries
- pve/pvp ranking entries
- message composer wrappers

### Training

Target module:

- `lib/moba_web/v2/components/training_components.ex`

Responsibilities:

- training header
- farming tabs
- target cards
- boss/gank/mine/meditation sections
- dead state
- pending battle banner

### Profile / Hero / Library

Target modules:

- `lib/moba_web/v2/components/profile_components.ex`
- `lib/moba_web/v2/components/library_components.ex`

Responsibilities:

- player profile summary
- hero history/collection cards
- manual/info blocks
- glossary/stat explanation rows

## Layer 5: Stateful Units

Purpose: genuinely stateful interactive widgets.

Allowed modules:

- tutorial overlay
- shop interaction surface
- any future isolated async widget

Current candidates:

- `lib/moba_web/v2/components/tutorial_component.ex`
- `lib/moba_web/v2/live/components/shop_component.ex`

Rules:

- Keep this set small.
- If a LiveComponent only renders markup and forwards events, it should probably become a function component.

## File Organization Plan

Target structure:

```text
lib/moba_web/v2/
  layouts.ex
  components/
    core_components.ex
    layout_components.ex
    game_components.ex
    game_helpers.ex
    create_components.ex
    training_components.ex
    battle_components.ex
    pvp_components.ex
    community_components.ex
    profile_components.ex
    library_components.ex
    hero_bar_components.ex
    shop_components.ex
    tutorial_component.ex
  live/
    create_live.ex
    training_live.ex
    battle_live.ex
    arena_live.ex
    dashboard_live.ex
    hero_live.ex
    player_live.ex
    community_live.ex
    library_live.ex
    duel_live.ex
    match_live.ex
    tavern_live.ex
```

Notes:

- Keep page ownership in `live/`.
- Keep shared rendering logic in `components/`.
- Avoid new top-level `views/`.
- Avoid mixing “page section components” into LiveView modules once they are shared.

## Naming Rules

- Use `MobaWeb.V2.Components.*` for function-component modules.
- Use `MobaWeb.V2.*Live` for routed LiveViews.
- Use `MobaWeb.V2.*Component` only for actual LiveComponents.
- Prefer names by domain, not by old template path.

Good:

- `BattleComponents`
- `TrainingComponents`
- `CreateComponents`
- `ProfileComponents`

Avoid:

- `SharedStuff`
- `MiscComponents`
- `Helpers2`

## Phoenix 1.8 Conventions To Follow

- Routed pages should be real LiveViews.
- Use `<Layouts.app ...>` at the top of every live template.
- Use `<.link navigate={...}>` and `<.link patch={...}>` instead of old navigation helpers.
- Use `<.form>` and `to_form/2` for forms.
- Prefer function components over `live_render` and view-driven partials.
- Keep template comments in HEEx comment syntax.
- Use explicit component APIs instead of helpers that inject HTML.

## Bootstrap Preservation Rules

Because the visual system is intentionally staying Bootstrap-based:

- Keep current Bootstrap class names unless the extraction itself requires minor cleanup.
- Preserve important DOM IDs.
- Preserve class hooks used by existing JS.
- Preserve tooltip/modal/tab data attributes until JS is intentionally modernized.

What is allowed:

- wrapping repeated button groups into components
- extracting repeated cards into components
- passing class overrides through component attrs

What is not allowed in this migration:

- changing the page to Tailwind-first markup
- changing spacing or layout just because a component was extracted
- swapping icons or redesigning badges

## Technical Debt To Retire

These are explicit cleanup targets for the component plan.

### 1. Legacy helper dependency

Current issue:

- most major shared `v2` surfaces no longer depend on legacy `MobaWeb.GameHelpers`
- compatibility helpers still exist in the codebase, especially for legacy templates outside `v2`

Target:

- move needed formatting/description logic into `MobaWeb.V2.Components.GameHelpers`
- keep output visually identical

Status:

- `pvp_components.ex` is complete
- remaining work is mostly broader legacy coexistence, not the main `v2` shared surfaces

### 2. Raw HTML helper output

Current issue:

- some tooltip and battle/helper code still returns HTML strings
- `hero_stats_tooltip/2` is an explicit compatibility formatter, but still string-based
- battle-related formatting still has remaining raw-string debt, but one major raw path was removed from `BattleLive`

Target:

- replace with components such as `cooldown_badge`, `resource_cost_badge`, and `effect_badge`

Status:

- improved, but not finished
- still an active debt item

### 3. Repeated hero/item/skill markup

Current issue:

- most core hero/item/skill card-footer patterns are already centralized
- remaining duplication is now concentrated in battle-turn UIs, shop UIs, tavern/library-specific displays, and a few highly customized templates

Target:

- centralize into shared game/pvp component APIs

Status:

- major progress made
- still incomplete in battle- and shop-specific surfaces

### 4. Overgrown page templates

Current issue:

- several pages are now mostly composition-oriented
- some templates still remain large and page-heavy, especially dashboard, training, battle, and library content sections

Target:

- page templates should read like assembly code: sections composed from named components

Status:

- partial progress
- still a worthwhile ongoing refactor target

### 5. Stateful components with too much rendering logic

Current issue:

- the shop path mixes stateful behavior and heavy rendering

Target:

- keep stateful shell if needed, but move markup into reusable function components/templates

Status:

- in progress
- the rendering surface has started moving into `shop_components.ex`
- the LiveComponent shell still owns most state/event behavior, which is acceptable for now

## Remaining Work

The next steps should focus on the highest-value remaining duplication and the most structurally awkward modules.

### Priority 1: Battle turn surfaces

Still needs work in:

- effect/reward/description extraction from the remaining battle templates and helpers
- the larger non-icon battle composition around descriptions, effects, and summaries

Why:

- the icon/resource layer is now extracted
- the remaining battle debt is in the heavier description/effect/reward rendering paths

Likely target:

- `lib/moba_web/v2/components/battle_components.ex`

### Priority 2: Shop extraction

Still needs work in:

- section-level composition cleanup in:
  - `lib/moba_web/v2/live/components/shop_component.ex`
  - `lib/moba_web/v2/live/components/shop_component/shop.html.heex`
- possible extraction of the remaining transmute form/action area if it starts to grow again

Why:

- this is still one of the most rendering-heavy stateful surfaces
- the low-level repeated display pieces are extracted, but the larger shop screen is still assembled in one big template

Likely target:

- keep the LiveComponent shell if needed
- move rendering into `shop_components.ex` or embedded templates owned by a shop component module

### Priority 3: Training section extraction

Still needs work in:

- training headers
- target/boss/dead-state/farm-tab section ownership
- remaining large training template composition

Why:

- some repeated display fragments are fixed already, but page-level section ownership is still mixed

Likely target:

- `lib/moba_web/v2/components/training_components.ex`

### Priority 4: Dashboard/Profile section extraction

Still needs work in:

- `dashboard_live.html.heex`
- `player_live.html.heex`
- larger profile/dashboard collection and summary blocks

Why:

- the shared primitives are now there
- the remaining work is mostly section extraction, not low-level display work

Likely target:

- `profile_components.ex`
- possibly smaller dashboard/profile section modules if needed

### Priority 5: Community and library section modules

Still needs work in:

- page-level extraction of `community` blocks
- page-level extraction of `library` informational blocks

Why:

- lower urgency than battle/shop/training
- mostly a composition cleanup now that some display primitives already exist

### Priority 6: HTML-string tooltip/effect cleanup

Still needs work in:

- explicit battle/effect/reward helpers that still emit HTML strings
- compatibility tooltip helpers that are still string-based

Why:

- this is the remaining conceptual mismatch with the “HEEx-first” goal
- it is important, but riskier than the display-component extractions above

## Suggested Current Order

If work continues from here, the most sensible order is:

1. battle turn components
2. shop rendering extraction
3. training section components
4. dashboard/profile section components
5. community/library section cleanup
6. final HTML-string helper retirement

## Migration Strategy

This should be done incrementally.

## Phase 1: Stabilize Boundaries

Success criteria:

- No new `v2` UI goes into legacy helper modules.
- No new raw HTML helper output is added.
- New shared UI lands in `components/`, not directly in page templates.

Tasks:

- declare target component ownership before each refactor
- keep LiveViews thin
- stop expanding `LegacyGH` usage

## Phase 2: Extract High-Reuse UI

Highest-value first:

1. hero display fragments
2. stat/resource badge rows
3. reward blocks
4. arena/player/community summary cards
5. create flow sections

Success criteria:

- the same hero card/stat row is reused in at least 2-3 screens

## Phase 3: Replace HTML-String Helpers

Tasks:

- convert cooldown/resource/effect HTML helpers to HEEx components
- move tooltip body generation to text/data helpers where possible

Success criteria:

- no new `raw("<span...")` component-like helpers in `v2`

## Phase 4: Reduce LiveComponent Surface Area

Tasks:

- review tutorial and shop
- keep only truly stateful pieces as LiveComponents
- convert render-only units to function components

Success criteria:

- every remaining LiveComponent has a clear state/lifecycle reason

## Phase 5: Finish Domain Coverage

Tasks:

- each major screen family has a matching component module
- LiveViews become mostly orchestration and event handling

Success criteria:

- screen templates are mostly composed from named components/embedded templates

## Suggested Extraction Order

This order gives the best payoff with the least churn.

1. `CreateLive`
2. `HeroBar` and shop rendering split
3. shared hero/stat/item/skill fragments
4. battle badges/effects/reward blocks
5. arena/player/community shared cards
6. library/profile informational sections

## Testing Expectations

For each extraction:

- preserve existing DOM IDs when tests depend on them
- add or update focused LiveView tests for key interactions
- test presence of key elements rather than full HTML blobs
- if a section becomes a shared component, ensure at least one screen-level test still covers it

Good verification examples:

- create flow still shows `#randomize-button`
- training still shows the same shop trigger and target actions
- arena still exposes the same duel/match action IDs

## Definition of Done

The component system is in a good state when:

- `v2` pages mostly compose named components instead of duplicating markup
- legacy `MobaWeb.GameHelpers` is no longer needed by `v2`
- raw HTML UI builders are gone from `v2`
- LiveComponents are rare and justified
- layout, game, battle, create, training, and profile concerns have clear module ownership
- the app still looks the same

## Immediate Next Steps

The first concrete implementation pass should be:

1. Extract `CreateLive` UI into `CreateComponents`
2. Move create-specific HEEx helper fragments out of `create_live.ex`
3. Define reusable hero/stat/action subcomponents used by create and dashboard
4. Replace any create-flow raw/duplicated fragments with those components

This is the smallest useful slice that improves structure without forcing a visual rewrite.
