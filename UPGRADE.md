# UPGRADE.md — Infra-Only Frontend Modernization Plan

## Goal

Upgrade the frontend infrastructure to modern Phoenix/LiveView patterns while keeping the current product behavior and screen design effectively the same.

This is a safety-first migration:

- Keep v1 live during migration
- Rebuild screens under `/v2` gradually
- Preserve existing UX flows and gameplay behavior
- Cut over only after parity is verified

---

## Explicit Scope

### In scope

- Move from legacy LiveView/template patterns to modern patterns
- Replace layout-level `live_render` processes with `on_mount` + function components
- Replace partial/template sprawl with colocated LiveView templates and component modules
- Keep dual asset pipelines during migration (`assets/` and `assets_v2/`)
- Add/expand LiveView tests for v2 screens and event flows
- Upgrade framework dependencies safely (LiveView 1.x path)

### Out of scope

- Visual redesign
- New game features
- Gameplay mechanics changes
- Reworking copy/content unless required for technical migration

---

## Design Direction

Keep the current design language. Do not adopt WC3UI, WarcraftCN, or any new visual framework as part of this migration.

If any temporary v2 styling diverges from v1 visuals, treat it as migration debt and normalize before cutover.

---

## Migration Principles

1. **Behavior parity over speed**
   - Every migrated screen must behave the same as v1 for key flows.

2. **Small vertical slices**
   - Migrate one screen/flow at a time instead of sweeping refactors.

3. **No mixed concerns**
   - Separate infra upgrades from feature work.

4. **Dual-run until confidence**
   - Keep v1 routes as fallback while v2 hardens.

5. **Test gates per screen**
   - No cutover for a screen without parity checks and tests.

---

## Technical Target State

- Modern LiveView navigation and route helpers (`push_navigate`, `~p`)
- `on_mount` hooks for shared session/game state
- Function component architecture instead of underscore partial rendering
- Colocated `.html.heex` templates beside LiveView modules
- Minimal layout process complexity (single LiveView process per page)
- Legacy template/view stack removable after parity

---

## Current Baseline (Migration Context)

- Legacy frontend still relies on many underscore partials and view modules.
- Layout-level shared UI is process-based in v1 (`live_render` in layout).
- v2 foundation exists but covers only a small subset of routes today.
- v1 and v2 asset pipelines already coexist, which is the correct migration shape.

This baseline means the migration should stay additive and route-by-route until parity.

---

## Router and Session Blueprint

Keep v1 routes untouched while v2 grows in parallel under `/v2`.

Core pattern:

- v1 live session stays as-is
- v2 uses its own `live_session`
- v2 uses `on_mount` hooks for auth and shared game state
- v2 uses separate layout/root layout modules

Recommended v2 session wiring:

```elixir
live_session :v2_game,
  on_mount: [
    MobaWeb.V2.Hooks.RequireAuth,
    MobaWeb.V2.Hooks.LoadGameState
  ],
  layout: {MobaWeb.V2.Layouts, :app},
  root_layout: {MobaWeb.V2.Layouts, :root} do
  # /v2 routes
end
```

---

## Asset Pipeline Strategy (Keep Both Until Cutover)

Maintain strict separation throughout migration:

- `assets/` remains the v1 pipeline (existing webpack/bootstrap stack)
- `assets_v2/` remains the v2 pipeline (esbuild + tailwind)
- v1 root layout loads only v1 bundles
- v2 root layout loads only v2 bundles

Why this matters:

- avoids cross-style/script contamination
- enables safe, incremental route migration
- preserves rollback ability during parity work

Do not merge pipelines early. Consolidate only after successful cutover and stabilization.

---

## Shared State and PubSub Contract

`LoadGameState` should remain the central place for assigning shared player/hero context to v2 pages.

Use the existing topic contract during migration (dash-separated, matching current broadcasts):

- `"player-#{player_id}"` for player updates (duel challenges, etc.)
- `"hero-#{hero_id}"` for hero updates (training state changes)
- `"player-ranking"` for ranking updates
- `"hero-ranking"` for hero ranking updates
- `"community"` for community updates

Parity requirement:

- if a v1 screen reacts to one of these topics, the v2 version must react equivalently.

---

## Modern LiveView Features To Adopt (Infra, Not UX)

Adopt these where they reduce complexity or memory without changing behavior:

- `assign_async` for non-blocking data fetches on mount
- `stream` / `stream_insert` / `stream_delete` for list-heavy views
- `render_with` for disconnected skeleton render of heavy pages
- `attach_hook` to split large event handlers by concern
- `push_event(..., dispatch: :before)` only for behavior-equivalent JS timing needs
- `static_changed?` for deploy refresh notification handling

These are implementation upgrades, not product changes.

---

## Recommended Sequence

## Phase 0 — Stabilize Direction (1-2 days)

- Freeze migration objective as infra-only and parity-first
- Define parity acceptance criteria per screen
- Create v2 test folder structure (`test/moba_web/v2/live/...`)
- Document v1 routes/features checklist to track completion

Exit criteria:

- Team agrees to "same screens, same behavior"
- Parity checklist template exists and is used

## Phase 1 — Foundation Hardening (2-4 days)

- Finalize `/v2` live session hooks (`RequireAuth`, `LoadGameState`)
- Keep v2 layouts and component scaffolding focused on existing visual language
- Ensure v2 asset pipeline supports current styles/components without redesign
- Add baseline tests for hooks and v2 dashboard mount/render

Exit criteria:

- `/v2` chrome works reliably with auth/session/game-state wiring
- First v2 tests run in CI/local

## Phase 2 — Framework Upgrade Pass (2-4 days)

- Upgrade LiveView toward 1.x in isolated PR(s)
- Resolve deprecations and compatibility issues without changing UX behavior
- Keep v1 and v2 both working after upgrade

Exit criteria:

- App compiles and tests pass with upgraded LiveView
- No user-facing flow regressions in smoke checks

## Phase 3 — Read-Only Screens (4-7 days)

Migrate low-risk screens first:

- Library
- Community
- Player
- Hero

For each screen:

- Port LiveView/module/template
- Replace partial rendering with function components
- Keep selectors, labels, and visual structure close to v1
- Add parity tests (mount + key content + navigation)

Exit criteria:

- All read-only screens function under `/v2`
- Tests cover basic parity paths

## Phase 4 — Core Interaction Screens (5-9 days)

Migrate:

- Dashboard
- Create
- Tavern

For each screen:

- Port events without behavior drift
- Reuse backend context functions (no gameplay changes)
- Add tests for all user actions and state branches

Exit criteria:

- Hero create/start flows work identically under `/v2`
- Dashboard state transitions match v1 behavior

## Phase 5 — Training + Battle (7-12 days)

Highest risk area:

- Training
- Battle
- Battles list/history

Approach:

- Migrate with strict event-by-event parity
- Keep state machine behavior identical
- Add robust tests for dead/alive/boss/farm/buyback/level/item interactions
- Validate redirects and timing-sensitive behavior

Exit criteria:

- End-to-end create -> training -> battle -> progress loop works in `/v2`

## Phase 6 — Arena + Duel + Match (7-12 days)

Migrate real-time/PubSub-heavy flows:

- Arena index
- Arena edit/team management
- Duel
- Match

Approach:

- Preserve existing duel/match state flow and timing semantics
- Validate two-client scenarios for realtime behavior
- Add tests for picks, transitions, and results

Exit criteria:

- Full PvP loop works in `/v2` with parity checks passing

## Phase 7 — Parity Audit + Cutover Prep (3-5 days)

- Route-by-route parity audit
- Regression pass on all key gameplay loops
- Verify auth/session behavior, reconnect behavior, and empty states
- Validate performance baseline and memory footprint

Exit criteria:

- All screens and key flows pass parity checklist
- v2 is cutover-ready

## Phase 8 — Cutover + Cleanup (2-4 days)

- Switch default routes to v2 (keep temporary fallback strategy)
- Monitor and soak test
- Remove v1 frontend layers after stabilization window

Post-cutover cleanup:

- Remove legacy partials/views and layout-level `live_render` architecture
- Remove old route wiring no longer used
- Consolidate assets when safe

---

## Parity Checklist (Per Screen)

- Mounts successfully for authenticated user
- Same key UI states as v1 (empty/loading/error/success where applicable)
- All click/submit/change events mapped and functional
- Same redirect/navigation outcomes
- Same PubSub update behavior (if real-time)
- Same critical validation messages and guardrails
- No gameplay side effects changed

---

## WC3-Related Removal Plan

This migration no longer includes WC3-specific visual work. Remove WC3-specific direction and artifacts from active migration scope.

### Remove from planning/docs

- WC3UI adoption tasks
- WarcraftCN styling spike tasks
- Any references that imply redesign is part of infra upgrade

### Remove from active implementation scope

- WC3-only asset conversion scripts and related dependencies
- WC3-only CSS/class contracts that are not needed for parity
- Any v2 component API assumptions tied to WC3-specific visuals

### Keep only what is needed

- Keep `assets_v2` pipeline and v2 component architecture
- Keep any neutral code that supports migration safety and parity
- Keep visual output aligned with current production design

---

## V1 Routes Parity Checklist

Track migration status for each v1 route. A route is "done" when its v2 equivalent
passes the per-screen parity checklist above.

| V1 Route | LiveView | Risk | Phase | Status |
|---|---|---|---|---|
| `/base` | `DashboardLive` | Low | 4 | v2 scaffold exists |
| `/invoke` | `CreateLive` | Medium | 4 | Not started |
| `/training` | `TrainingLive` | High | 5 | Not started |
| `/battles` | `BattlesLive` | Medium | 5 | Not started |
| `/battles/:id` | `BattleLive` | High | 5 | Not started |
| `/arena` | `ArenaLive.Index` | High | 6 | Not started |
| `/arena/edit` | `ArenaLive.Edit` | High | 6 | Not started |
| `/arena/:id` | `DuelLive` | High | 6 | Not started |
| `/matches/:id` | `MatchLive` | High | 6 | Not started |
| `/user/:id` | `PlayerLive` | Low | 3 | Not started |
| `/player/:player_id` | `PlayerLive :show` | Low | 3 | Not started |
| `/hero/:id` | `HeroLive` | Low | 3 | Not started |
| `/tavern` | `TavernLive` | Medium | 4 | Not started |
| `/community` | `CommunityLive` | Low | 3 | Not started |
| `/library` | `LibraryLive` | Low | 3 | Not started |

---

## Risk Controls

- Do not migrate multiple high-risk screens in a single PR
- Keep rollback path during cutover window
- Prefer additive migration over destructive replacement
- Use checklist-based signoff per route before declaring parity

---

## Rough Timeline

For a single focused developer, this is typically a 6-9 week effort end-to-end when done safely with parity gates.

Use this only as planning guidance; route complexity can shift estimates.

---

## Definition of Done

Migration is complete when:

- `/v2` fully replaces v1 for all user-facing game screens
- User experience and gameplay behavior are materially unchanged
- Legacy frontend infrastructure is removed safely
- Remaining frontend codebase follows modern LiveView patterns and is test-backed
