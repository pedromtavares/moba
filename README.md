# MOBA - Multiplayer Online Battle Arena

![Test Suite](https://github.com/pedromtavares/moba/workflows/Test%20Suite/badge.svg)
[![Discord](https://img.shields.io/badge/chat-discord-7289da.svg)][discord]

A turn-based RPG built with Phoenix LiveView. Online since 2020 with over 1500 players.

### [`PRESS START`](https://browsermoba.com/)

## Features
 * Choose from a roster of 20 avatars, 20+ abilities and 25+ items to train your custom hero in a complete PvE mode
 * Battle your way through 7 leagues and a boss fight to compete for the fastest game completion time
 * Master all playstyles with full account level progression to compete in a season leaderboard
 * Competitive PvP mode featuring 5v5 team battles with skill brackets and 1v1 real-time duels

### Requirements
 * PostgreSQL 15
 * Elixir 1.16.2
 * Erlang 26.2.4
 * node.js 20.14.0

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
