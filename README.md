# MOBA - Multiplayer Online Battle Arena

![Test Suite](https://github.com/pedromtavares/moba/workflows/Test%20Suite/badge.svg)
[![Discord](https://img.shields.io/badge/chat-discord-7289da.svg)][discord]

# ![MOBA](assets/static/images/favicon.png)

A community-made turn-based RPG built with Phoenix LiveView.

 * <a href="https://browsermoba.com/" target="_blank">Play</a>
 * [Get Involved](#get-involved)
 * [Game Manual](#game-manual)
 * [Battle Engine](#battle-engine)

## Get Involved
MOBA is an opportunity to get your feet wet with Phoenix LiveView (or even Elixir) beyond simple counter demos. It's first and foremost a fun learning experience for all developer skill levels, while also being an actual product with real users deployed in a production environment. Interested? [Get Involved.](https://github.com/pedromtavares/moba/issues/90)

### Requirements
 * PostgreSQL 12
 * Elixir 1.10
 * Erlang 21
 * node.js 13.5

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


## Game Manual

It is highly advised that you [play the game](https://browsermoba.com) for at least an hour to get a general sense of the gameplay. The following topics will go into further detail of how most things in the `Game` domain works.


### Main game loop

MOBA is currently played through daily matches where players fight against each other through turn-based 1-on-1 interactive battles. Each player starts out by creating a Hero that will be used throughout the two phases of the game: the Jungle (PvE) and the Arena (PvP).

#### Hero Creation

![Hero Creation](https://i.imgur.com/fRVDNOs.png)

The first screen the user is taken to (after the homepage) is to create a new Hero. There, they must first pick an Avatar, which provides a baseline of attributes for your hero as well as its strongest skill (ultimate). After picking the Avatar, the user can then pick one of the pre-defined Builds (or customize their own), which are a set of skills that can be used during a battle. Having a Build that properly sinergizes with your Avatar is the most critical choice of the game.



#### Jungle (PvE)

![Jungle](https://i.imgur.com/ecBqoKL.png)

This is the first phase of the game, where players have to level their newly created Hero by battling several generated targets to gain experience (XP), gold and Jungle Points (JP). These generated targets come in varying difficulties and rewards the player accordingly.

Players can also use their JPs to periodically play through a League Challenge and rank up through the Leagues (Bronze -> Silver -> ... -> Master) for further rewards. The main objective when leveling is to reach the Master League, which automatically levels a Hero to the maximum level (25).


#### Inventory

![Shop](https://i.imgur.com/htMMtzy.png/n5hu5oQ.png)

As you level up in the Jungle you also gain gold, which can be used to purchase Items. Items provide additional stats (attack, armor, speed, etc) as well as special effects that can be used in a battle. Each Hero can hold up to 6 items in their inventory.

Items are classified according to their price and overall strength. Items of the same class (rarity) can be merged into an item of a higher rarity, providing ways for users to tweak their strategy as the game progresses.

Having a strong build along with a sinergizing inventory is the key to winning battles and thus, the match.


#### Arena (PvP)

![Arena](https://i.imgur.com/GmfnGze.png)

Once all available battles in the Jungle are depleted, players are then invited to join the Arena. Here, players battle against each other for a spot on the match podium, where medals are awarded and used to ultimately rank the best players of the game overall. In order to join the Arena, the player must pick one of their existing heroes, meaning that once you have a few that you feel comfortable playing with, you essentially don't need to play through the Jungle phase anymore.

Unlike the Jungle, heroes in the Arena can no longer level up or gain gold, and the match ranking is decided solely by who has the most Season Points (SP). SPs are awarded on every battle based on a simple implementation of the ELO system, where battling lower-ranked players give you less points and battling higher-ranked players give you more.

The Arena is currently organized in 2 rounds (12 hrs each), where in each round every player can battle every other player exactly once. Also unlike the Jungle, these battles cannot end in a tie, awarding a victory to the defender if they manage to stay alive.

#### Game Server

A GenServer is always running in the background constantly checking the timers to either start a new Arena round or start a new match altogether. Once a new match is started, everything essentially resets, giving players the option to quickly join the Arena again for a fresh round or to create a new hero in the Jungle.

![Rewards](https://i.imgur.com/VRpfPYA.png)

When a `Match` finishes, rewards are given to the top 3 ranked heroes of the Arena. These players will win both Medals and Shards. Medals are what ultimately ranks players in the global user ranking. Shards are the in-game currency and can be used to unlock new Skills and Avatars to be used in future matches.

## Battle Engine

![Engine](https://i.imgur.com/PmSqQd4.png)

Each battle in the game is composed an attacker, a defender, and multiple turns which are individually processed based on whatever skills and items were used on that turn by both `Battlers`.

A battle finishes once either one of the battlers dies or the maximum number of turns (currently 10) is reached. The results and rewards of a battle are determined by the battle's type -- `Pve`, `Pvp` or `League`. For example: `Pve` battles may end on a tie (nobody dies) and partially rewards the attacker, whereas this does not happen on `Pvp` or `League` battles -- you will lose if you do not kill.

### Turn Processing

Each `Battler` gets up to 5 turns to defeat their opponent. These turns are alternated until the battle ends: attacker goes, defender goes, attacker goes, etc.

`Moba.Engine.Core.Processor` defines the sequence in which a `Turn` is processed. In a nutshell, when a user orders a skill to be used (and optionally an item as well) via the UI, the processor applies the effects of that skill and any other passive effects the attacker has, also taking into consideration any defense mechanism the defender may have, and outputs a new state of both battlers that is then fed into a new Turn. This process repeats until the battle is over.

```elixir
# file: engine/core/processor.ex (simplified)
  def process_turn(turn) do
    turn
    |> attack()
    |> passives()
    |> defend()
    |> finish()
  end

  defp attack(turn) do
    turn
    |> use_skill()
    |> use_item()
  end

  defp finish(%{attacker: turn_attacker, defender: turn_defender} = turn) do
    finalized_attacker = finalize_attacker(turn_attacker, turn_defender)
    finalized_defender = finalize_defender(turn_defender)

    %{turn | attacker: finalized_attacker, defender: finalized_defender}
  end

  defp finalize_attacker(attacker, defender) do
    %{
      attacker
      | current_hp: Helper.calculate_final_hp(attacker),
        current_mp: Helper.calculate_final_mp(attacker),
        armor: Helper.total_armor(attacker),
        power: Helper.final_power(attacker, defender)
    }
  end

```

It's important to note that all battles are currently single-player, meaning that the defender always acts automatically. In the Arena, players can define skill and item orders to be used when defending, but they do not actively participate in that defense (players would need to be constantly online for a feature like this to properly work).

### Spells and Effects

`Skills` and `Items` are abstracted as `Spells` in the battle engine. Each `Spell` has a collection of special `Effects` associated with it, take the example of the skill Death Pulse, which deals damage to the defender and regenerates the caster (attacker):

```elixir
# file: engine/core/spell.ex
  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "death_pulse" do
    turn
    |> Effect.base_damage()
    |> Effect.hp_regen_by_base_amount()
  end

# file: engine/core/effect.ex
  def base_damage(%{resource: %{base_damage: base_damage}} = turn) do
    update_defender_number(turn, :damage, base_damage)
  end
  def hp_regen_by_base_amount(%{resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, resource.base_amount)
  end

```

Each `Effect` updates either the `defender` or the `attacker`, returning a modified `Turn` struct that gets passed down the pipeline (via the turn `Processor` shown in the previous section) and saved to the `Battle` in its final state once the processing is done.

In essence, all a particular `Effect` does is update one of the fields of the `Battler` struct, like `damage`, `hp_regen`, `stunned`, `silenced`, [and many more](lib/moba/engine/schema/battler.ex). It's these interactions between effects that generate nearly infinite different battle outcomes.


[discord]: https://discord.gg/wA3JxVU
