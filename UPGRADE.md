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

## Phase 0 — Config & Endpoint Modernization

Bring config files, endpoint, and mix.exs up to Phoenix 1.8 baseline. No behavior changes, no new features.

### Step 0.1 — mix.exs: Add `compilers` and `listeners`

In `mix.exs`, inside the `project/0` function, add these two keys to the keyword list:

```elixir
compilers: [:phoenix_live_view] ++ Mix.compilers(),
listeners: [Phoenix.CodeReloader]
```

These are required for correct LiveView template compilation and automatic code reloading in 1.8.

Verify: `mix compile` succeeds.

### Step 0.2 — mix.exs: Add `lazy_html` test dependency

In `mix.exs`, inside the `deps/0` function, add:

```elixir
{:lazy_html, ">= 0.1.0", only: :test}
```

This is the modern test assertion library for LiveView 1.1+ (replaces `floki` for LV test helpers).

Verify: `mix deps.get` succeeds.

### Step 0.3 — config/config.exs: Fix `import_config` deprecation

In `config/config.exs`, change the last line from:

```elixir
import_config "#{Mix.env()}.exs"
```

to:

```elixir
import_config "#{config_env()}.exs"
```

`Mix.env()` in config files triggers a deprecation warning. `config_env()` is the correct replacement.

Verify: `mix compile` produces no warning about `Mix.env()` in config.

### Step 0.4 — config/config.exs: Update `render_errors` format

In `config/config.exs`, find the endpoint config block and change:

```elixir
render_errors: [view: MobaWeb.ErrorView, accepts: ~w(html json)]
```

to:

```elixir
render_errors: [formats: [html: MobaWeb.ErrorView, json: MobaWeb.ErrorView], layout: false]
```

The `view:` key is deprecated in Phoenix 1.8. The `formats:` key is required. We point both formats at the existing `ErrorView` module for now — it still works. A proper `ErrorHTML`/`ErrorJSON` split can happen later.

Verify: `mix compile` succeeds. Visiting a nonexistent route in dev shows the error page.

### Step 0.5 — config/config.exs: Add `generators` config

In `config/config.exs`, after the `ecto_repos` line, add:

```elixir
generators: [timestamp_type: :utc_datetime]
```

So the block looks like:

```elixir
config :moba,
  ecto_repos: [Moba.Repo],
  env: Mix.env(),
  admin_refresh_seconds: System.get_env("ADMIN_REFRESH_SECONDS") || "1000000000",
  generators: [timestamp_type: :utc_datetime]
```

This ensures any future generated migrations use `utc_datetime` columns.

Verify: `mix compile` succeeds.

### Step 0.6 — config/test.exs: Add runtime check configs

In `config/test.exs`, add these lines (anywhere, but after the `import Config` line):

```elixir
# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
```

These speed up test compilation and catch LiveView issues early.

Verify: `mix test` still passes.

### Step 0.7 — mix.exs: Replace `plug_cowboy` with `bandit`

In `mix.exs`, inside the `deps/0` function, find:

```elixir
{:plug_cowboy, "~> 2.2"},
```

Replace with:

```elixir
{:bandit, "~> 1.5"},
```

Bandit is the default HTTP server in Phoenix 1.8. It is faster, pure-Elixir, and actively maintained. Cowboy still works but is no longer the default.

Then in `config/config.exs`, inside the endpoint config block, add:

```elixir
adapter: Bandit.PhoenixAdapter,
```

So the block starts like:

```elixir
config :moba, MobaWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
```

Run `mix deps.get` after changing the dependency.

Verify: `mix deps.get` succeeds. `mix compile` succeeds. App boots in dev (`mix phx.server`).

### Step 0.8 — mix.exs: Add heroicons vendored dependency

In `mix.exs`, inside the `deps/0` function, add:

```elixir
{:heroicons,
 github: "tailwindlabs/heroicons",
 tag: "v2.2.0",
 sparse: "optimized",
 app: false,
 compile: false,
 depth: 1},
```

The `<.icon name="hero-...">` component in `core_components.ex` references heroicon CSS classes. The v2 asset pipeline needs the vendored icon files to generate the CSS. Without this dep, hero icons render as empty spans.

Note: the v1 pipeline may handle icons differently (e.g. via webpack). This dependency is primarily needed for the v2/Tailwind pipeline. The v2 `assets_v2/vendor/heroicons.js` plugin (or equivalent) reads from `deps/heroicons` to generate icon CSS.

Verify: `mix deps.get` succeeds.

### Step 0.9 — mix.exs: Add `dns_cluster` dependency

In `mix.exs`, inside the `deps/0` function, add:

```elixir
{:dns_cluster, "~> 0.2.0"},
```

Then in `lib/moba/application.ex`, add this child to the `children` list, before the `MobaWeb.Endpoint` entry:

```elixir
{DNSCluster, query: Application.get_env(:moba, :dns_cluster_query) || :ignore},
```

DNSCluster enables automatic node clustering via DNS in production (e.g. on Fly.io or Kubernetes). When the query is `:ignore` (the default), it does nothing — no behavior change.

Verify: `mix deps.get` succeeds. `mix compile` succeeds. App boots in dev.

### Step 0.10 — config/dev.exs: Add LiveView debug annotations

In `config/dev.exs`, add these lines (after the existing `config :phoenix, :plug_init_mode, :runtime` line):

```elixir
config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
```

These add source location annotations to rendered HTML in dev, making it easy to find which template/component generated a given piece of markup. The browser's DevTools will show the source file and line number for each element.

Verify: `mix compile` succeeds. In dev, inspect a page element in browser DevTools — you should see `data-phx-*` debug attributes.

### Step 0.11 — config/dev.exs: Add `web_console_logger` and modernize live_reload patterns

In `config/dev.exs`, find the `live_reload` block:

```elixir
config :moba, MobaWeb.Endpoint,
  live_reload: [
    patterns: [
```

Add `web_console_logger: true` before `patterns`:

```elixir
config :moba, MobaWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
```

`web_console_logger: true` streams server log output to the browser console in dev — very useful for debugging LiveView events without switching to the terminal.

Also add this pattern to the existing patterns list if not already present, to pick up changes in the v2 components directory:

```elixir
~r{lib/moba_web/(?:controllers|live|components|v2)/?.*\.(ex|heex)$}
```

Verify: `mix compile` succeeds. In dev, open the browser console — you should see server log lines appearing.

### Step 0.12 — config/prod.exs: Add Swoosh production config

In `config/prod.exs`, add these lines:

```elixir
# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false
```

Without this, Swoosh in production may silently fail to send emails because it defaults to the local adapter.

Note: this requires the `req` dependency. Check if it's already in deps. If not, add `{:req, "~> 0.5"}` to `mix.exs` deps.

Verify: `mix compile` succeeds.

### Step 0.13 — endpoint.ex: Replace `Plug.Logger` with `Plug.Telemetry`

In `lib/moba_web/endpoint.ex`, change:

```elixir
plug Plug.Logger
```

to:

```elixir
plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
```

`Plug.Telemetry` emits telemetry events that LiveDashboard uses for request logging. `Plug.Logger` is the older approach.

Verify: `mix compile` succeeds. LiveDashboard request logger still works in dev.

### Step 0.14 — endpoint.ex: Add `Phoenix.Ecto.CheckRepoStatus` in dev block

In `lib/moba_web/endpoint.ex`, inside the `if code_reloading? do` block, add this line after `plug Phoenix.CodeReloader`:

```elixir
plug Phoenix.Ecto.CheckRepoStatus, otp_app: :moba
```

So the block becomes:

```elixir
if code_reloading? do
  socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
  plug Phoenix.LiveReloader
  plug Phoenix.CodeReloader
  plug Phoenix.Ecto.CheckRepoStatus, otp_app: :moba
end
```

This shows a helpful error page in dev when migrations are pending.

Verify: `mix compile` succeeds.

### Step 0.15 — endpoint.ex: Add `same_site` to session options

In `lib/moba_web/endpoint.ex`, add `same_site: "Lax"` to the `@session_options` list:

```elixir
@session_options [
  store: :cookie,
  key: "_moba_key",
  signing_salt: "5hkIoMFs",
  max_age: 24 * 60 * 60 * 37,
  same_site: "Lax"
]
```

Security best practice to prevent CSRF via cross-site requests.

Verify: `mix compile` succeeds. Log in still works in dev.

### Step 0.16 — endpoint.ex: Fix static file gzip setting

In `lib/moba_web/endpoint.ex`, change the first `Plug.Static` block from:

```elixir
gzip: false,
```

to:

```elixir
gzip: not code_reloading?,
```

This enables gzip for static files in production but keeps it off during development.

Verify: `mix compile` succeeds.

### Phase 0 exit criteria

- `mix compile` succeeds with no deprecation warnings about `Mix.env()` in config
- `mix test` passes
- App boots and serves pages in dev
- All changes are config/infra only — no behavior changes

---

## Phase 1 — Web Module & Auth Modernization

Update `moba_web.ex`, `core_components.ex`, and `gettext` usage to 1.8 patterns. Keep v1 working.

### Step 1.1 — moba_web.ex: Add `helpers: false` to router macro

In `lib/moba_web.ex`, inside the `router/0` function, change:

```elixir
use Phoenix.Router
```

to:

```elixir
use Phoenix.Router, helpers: false
```

This disables the deprecated `Routes` helpers. v1 code that uses `Routes.xxx_path(...)` will break, so this step must be paired with Step 1.2.

Verify: `mix compile` — note any compilation errors referencing `Routes`.

### Step 1.2 — moba_web.ex: Remove `Routes` alias from helpers

In `lib/moba_web.ex`, inside the `html_helpers/0` function, remove this line:

```elixir
alias MobaWeb.Router.Helpers, as: Routes
```

And inside the `controller/0` function, remove this line:

```elixir
alias MobaWeb.Router.Helpers, as: Routes
```

Then search the entire codebase for `Routes.` references. Each one must be replaced with the equivalent `~p"/path"` verified route. Common patterns:

- `Routes.live_path(socket, SomeLive)` → `~p"/some-path"`
- `Routes.game_path(conn, :index)` → `~p"/"`

**Scope warning**: There are ~120 `Routes.` usages across ~60 files (templates, controllers, LiveViews, admin views). This is a large conversion. Approach it in sub-batches:

1. First pass: LiveView modules (`lib/moba_web/live/*.ex`) — ~10 references
2. Second pass: Controllers (`lib/moba_web/controllers/`) — ~20 references
3. Third pass: Templates (`lib/moba_web/templates/`) — ~70 references
4. Fourth pass: Admin templates/controllers (`lib/moba_web/controllers/admin/`) — ~20 references

After each sub-batch, run `mix compile` to verify. The app must compile after each sub-batch because `helpers: false` (Step 1.1) makes any remaining `Routes.` reference a compilation error.

Alternative approach: Do Step 1.1 last (after all `Routes.` references are converted). Convert all references first while the code still compiles with both styles, then flip `helpers: false` as the final step.

Verify: `mix compile` succeeds. `mix test` passes. `rg 'Routes\.' lib/ --type elixir` returns zero matches (excluding UPGRADE.md).

### Step 1.3 — moba_web.ex: Update Gettext usage to backend syntax

In `lib/moba_web.ex`, in every place that has:

```elixir
import MobaWeb.Gettext
```

Replace with:

```elixir
use Gettext, backend: MobaWeb.Gettext
```

This appears in: `controller/0`, `live_view/0`, `v2_live_view/0`, `html_helpers/0`, and `v2_html_helpers/0`. Change all of them.

Verify: `mix compile` succeeds. No warnings about deprecated Gettext usage.

### Step 1.4 — moba_web.ex: Alias `MobaWeb.Layouts` in v2 html helpers

In `lib/moba_web.ex`, inside `v2_html_helpers/0`, verify that this alias exists. If not, add it:

```elixir
alias MobaWeb.V2.Layouts
```

This is needed so v2 LiveView templates can use `<Layouts.app flash={@flash}>`.

Verify: `mix compile` succeeds.

### Step 1.5 — core_components.ex: Add `used_input?` guard

In `lib/moba_web/core_components.ex`, find the `input/1` function clause that pattern matches on `%HTML.FormField{}`:

```elixir
def input(%{field: %HTML.FormField{} = field} = assigns) do
  assigns
  |> assign(field: nil, id: assigns.id || field.id)
  |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
```

Change the errors line to:

```elixir
def input(%{field: %HTML.FormField{} = field} = assigns) do
  errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

  assigns
  |> assign(field: nil, id: assigns.id || field.id)
  |> assign(:errors, Enum.map(errors, &translate_error(&1)))
```

This prevents form validation errors from showing before the user has interacted with the field.

Verify: `mix compile` succeeds.

### Step 1.6 — core_components.ex: Update HEEx interpolation syntax

In `lib/moba_web/core_components.ex`, replace all `<%= render_slot(...) %>` with `{render_slot(...)}` and `<%= msg %>` with `{msg}` and similar `<%= @var %>` with `{@var}`.

Specifically, search for `<%= ` in the file and convert each occurrence:

- `<%= render_slot(@inner_block) %>` → `{render_slot(@inner_block)}`
- `<%= render_slot(action) %>` → `{render_slot(action)}`
- `<%= msg %>` → `{msg}`
- `<%= @label %>` → `{@label}`
- `<%= Form.options_for_select(@options, @value) %>` → `{Form.options_for_select(@options, @value)}`
- `<%= Form.normalize_value("textarea", @value) %>` → `{Form.normalize_value("textarea", @value)}`

**Important**: Only convert `<%= %>` that are inside tag bodies (between `>` and `<`). Do NOT convert `<%= %>` that are used in block constructs like `<%= if ... do %>` or `<%= for ... do %>` — those must stay as `<%= %>`.

Verify: `mix compile` succeeds. Forms render correctly in dev.

### Step 1.7 — Upgrade v2 asset pipeline to Tailwind v4

The v2 pipeline currently uses Tailwind v3.4.17 with a `tailwind.config.js` file. Phoenix 1.8 defaults to Tailwind v4, which uses a CSS-based configuration instead.

**Step 1.7a** — In `config/config.exs`, update the tailwind version and config:

Change:

```elixir
config :tailwind,
  version: "3.4.17",
  v2: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/v2/assets/app.css
    ),
    cd: Path.expand("../assets_v2", __DIR__)
  ]
```

To:

```elixir
config :tailwind,
  version: "4.1.7",
  v2: [
    args: ~w(
      --input=assets_v2/css/app.css
      --output=priv/static/v2/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]
```

Note the changes: Tailwind v4 no longer uses `--config`. The `cd` changes to the project root because Tailwind v4 resolves paths relative to the input file.

**Step 1.7b** — Update `assets_v2/css/app.css` to use Tailwind v4 import syntax.

Replace any Tailwind v3 directives at the top of the file:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

With the Tailwind v4 import syntax:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/moba_web";
```

The `source(none)` disables auto-detection, and the `@source` directives tell Tailwind v4 where to scan for classes.

**Step 1.7c** — Delete `assets_v2/tailwind.config.js` if it exists. Tailwind v4 no longer uses a JS config file. If you have custom theme values or plugins defined in it, migrate them to `@theme` blocks in `app.css`. See https://tailwindcss.com/docs/upgrade-guide for migration details.

**Step 1.7d** — Run `mix tailwind.install --if-missing` to get the Tailwind v4 binary, then run `mix tailwind v2` to verify the build.

Verify: `mix tailwind v2` succeeds. The output CSS at `priv/static/v2/assets/app.css` contains expected styles. v2 pages render correctly in dev.

### Step 1.8 — Plan `phoenix_view` and `phoenix_html_helpers` removal (do not remove yet)

The following deps are v1 compatibility shims that should be removed after cutover:

- `{:phoenix_view, "~> 2.0"}` — used by 17 view modules in `lib/moba_web/views/`
- `{:phoenix_html_helpers, "~> 1.0"}` — used via `use PhoenixHTMLHelpers` in `html_helpers/0`

**Do NOT remove these yet.** The entire v1 template/view stack depends on them. They will be removed in Phase 8 (post-cutover cleanup) after all v1 views and templates are retired.

For now, just verify they are not leaking into v2 code:

- Run `rg 'use MobaWeb, :view' lib/moba_web/v2/` — should return zero matches
- Run `rg 'PhoenixHTMLHelpers' lib/moba_web/v2/` — should return zero matches
- Run `rg 'Routes\.' lib/moba_web/v2/` — should return zero matches

If any v2 code references these, fix it to use modern patterns instead.

Verify: No v2 code imports `Phoenix.View`, `PhoenixHTMLHelpers`, or `Routes`.

### Phase 1 exit criteria

- `mix compile` succeeds with no warnings about deprecated `Routes` or `Gettext`
- `mix test` passes
- All v1 routes still work
- Forms don't show validation errors before user interaction
- v2 asset pipeline builds with Tailwind v4
- No v2 code depends on `Phoenix.View`, `PhoenixHTMLHelpers`, or `Routes`

---

## Phase 2 — Foundation Hardening

Finalize v2 session hooks, layouts, asset pipeline, and baseline tests.

### Step 2.1 — Finalize v2 live session hooks

Ensure `lib/moba_web/v2/hooks/require_auth.ex` and `lib/moba_web/v2/hooks/load_game_state.ex` exist and work correctly.

`RequireAuth` should:
- Read `user_token` from session
- Look up user via `Accounts.get_user_by_session_token/1`
- Assign `current_user` to socket
- Redirect to login if no user found

`LoadGameState` should:
- Read the current player and hero from the user
- Assign `current_player` and `current_hero` to socket
- Subscribe to relevant PubSub topics

Verify: Visiting `/v2/base` while logged in mounts successfully with assigns. Visiting while logged out redirects to login.

### Step 2.2 — Verify v2 layouts and root layout

Ensure `lib/moba_web/v2/layouts.ex` exists and defines both `:root` and `:app` layout functions.

The root layout should:
- Render the HTML skeleton (`<!DOCTYPE html>`, `<head>`, `<body>`)
- Include `<meta name="csrf-token" content={get_csrf_token()} />`
- Include `<.live_title>` component
- Load v2 assets via `<link href={~p"/v2/assets/app.css"}>` and `<script src={~p"/v2/assets/app.js"}>`
- Render `{@inner_content}`

The app layout should:
- Accept `flash` and `current_user` attrs
- Render `<.flash_group flash={@flash} />`
- Render `{render_slot(@inner_block)}`

Verify: `/v2/base` renders with correct layout, no asset 404s in browser console.

### Step 2.3 — Verify v2 asset pipeline

Ensure the esbuild and tailwind configs in `config/config.exs` for the `:v2` key point to the correct input/output paths and that `assets_v2/` contains the required `js/app.js` and `css/app.css` entry points.

Run in terminal:
```
mix esbuild v2
mix tailwind v2
```

Verify: Files are generated at `priv/static/v2/assets/app.js` and `priv/static/v2/assets/app.css`.

### Step 2.4 — Add baseline v2 tests

Create `test/moba_web/v2/live/dashboard_live_test.exs` if it doesn't exist. It should test:

- Authenticated user can mount `/v2/base`
- Unauthenticated user is redirected to login
- Page contains expected content (e.g. player name or dashboard heading)

Use `Phoenix.ConnTest` and `Phoenix.LiveViewTest` patterns. Use the `log_in_user` test helper from `test/support/conn_case.ex`.

Verify: `mix test test/moba_web/v2/` passes.

### Phase 2 exit criteria

- `/v2/base` renders correctly for authenticated users
- `/v2/base` redirects unauthenticated users to login
- v2 asset pipeline builds without errors
- At least one v2 LiveView test passes

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
