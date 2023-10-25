# MOBA - Multiplayer Online Battle Arena

![Test Suite](https://github.com/pedromtavares/moba/workflows/Test%20Suite/badge.svg)
[![Discord](https://img.shields.io/badge/chat-discord-7289da.svg)][discord]

# ![MOBA](assets/static/images/favicon.png)

A community-made turn-based RPG built with Phoenix LiveView.

 * <a href="https://browsermoba.com/" target="_blank">Play</a>

## Get Involved
MOBA is an opportunity to get your feet wet with Phoenix LiveView (or even Elixir) beyond simple counter demos. It's first and foremost a fun learning experience for all developer skill levels, while also being an actual product with real users deployed in a production environment. Interested? [Get Involved.](https://github.com/pedromtavares/moba/issues/90)

### Requirements
 * PostgreSQL 15
 * Elixir 1.14.1
 * Erlang 25.3.2.6
 * node.js 17.0.1

### Setup
  * Install dependencies with `mix deps.get`
  * Create, migrate and seed your database with `mix ecto.setup`
  * Install asset dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server` (in project root)

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser. You can login with the seeded admin account: `admin@browsermoba.com` `123456`

### Running tests
  The tests need the seeds file to be run on the test database.

  ```bash
  MIX_ENV=test mix ecto.setup
  mix test
  ```


[discord]: https://discord.gg/QNwEdPS
