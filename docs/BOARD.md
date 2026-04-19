# BOARD.md

## Overview

Base Survival is a turn-based PvE board mode that sits alongside Training and Arena:

- `Training`: build heroes through roguelite PvE
- `Arena`: competitive PvP using trained heroes
- `Base Survival`: turn-based macro PvE focused on pushing, defending, rotating, and surviving

This mode has:

- no farming
- no gold
- no consumable economy
- no ward items

The core gameplay is:

- choose `5` active heroes from your trained roster
- place them on your side of the board
- each turn, move, hold, or teleport them back to base
- create favorable fights
- keep heroes alive
- destroy enemy structures and Core before yours falls

## Design Goals

- Relaxing: no timer, player advances when ready
- Strategic: movement, positioning, vision, and composition matter
- Simple: few actions, but each action is meaningful
- MOBA-flavored: lanes, jungle routes, structures, ganks, fountain, rotations

## Match Rules

### Win / Loss

- Win by destroying the enemy `Core`
- Lose if your `Core` reaches `0 HP`

### Match Pace

- Fully turn-based
- Player clicks `Next Turn` when done
- No real-time countdown

## Roster Rules

### Active Roster

- Choose any `5` trained heroes as the active roster for the match
- All other trained heroes remain on the bench

### Bench Swaps

- Only heroes at `Fountain` with `100% HP` may be swapped out
- Swapped-in bench hero appears at `Fountain`
- Swapped-in hero cannot act until next turn

### Hero Equipment

- Heroes enter Base Survival with their existing equipped item builds from the main game
- Base Survival does not have its own item shop or economy

## Commands Per Turn

Each living active hero may do exactly one of:

- `Move` to an adjacent connected node
- `Hold`
- `Base Teleport`

### Move

- Move to one adjacent node
- All movement resolves simultaneously

### Hold

- Stay in the current node
- Hero still contests, defends, and fights normally

### Base Teleport

- Always available
- Hero immediately returns to `Fountain`
- Hero performs no other action that turn

## HP, Death, and Recovery

### Fountain Healing

- Fountain heals `20%` max HP per turn
- No healing outside Fountain

### Death

- Dead heroes return to `Fountain`
- Dead heroes return with `0% HP`

### Recovery

- Heroes recover only by staying at Fountain over turns
- A hero must be at `100% HP` to be swapped with a benched hero

## Turn Sequence

Each turn resolves in this order:

1. Player chooses commands for all living active heroes
2. Optional bench swaps are declared
3. Movement resolves simultaneously
4. Vision updates
5. Fights resolve on contested nodes
6. Structure damage applies on controlled uncontested nodes
7. Dead heroes are returned to Fountain
8. Fountain healing is applied
9. Player reviews updated board and clicks `Next Turn`

## Vision Rules

### Base Vision

Each hero reveals:

- their current node
- all adjacent connected nodes

### Structure Vision

- Friendly structures reveal their own node

### Hidden Movement

- If an enemy hero moves from a node you could not see, their path is hidden
- You only learn their location if they become visible again or start a fight

### Warding Replacement

This mode does not use wards or anti-wards.

Instead, vision is created by:

- hero positioning
- holding key junctions
- controlling jungle and river routes
- structure presence

Map control replaces ward control.

## Node State

### Controlled Node

A node is controlled by a team if:

- that team has at least one living hero on the node
- and the enemy has none

### Contested Node

A node is contested if:

- both teams have at least one living hero on the node after movement resolves

### Neutral Node

A node is neutral if:

- neither team occupies it

## Fight Rules

### When Fights Start

A fight happens whenever both teams occupy the same node after movement resolves.

### Who Is the Attacker

Base Survival uses a board-defined attacker, not the current standard battle initiator roll.

Rules:

1. If one side moved into a node already occupied by the other side, the moving side is the attacker.
2. If both sides moved into the same empty node, the side with higher total team speed on that node is the attacker.
3. If tied, the side that moved more heroes into the node this turn is the attacker.
4. If still tied and the node belongs to one side structurally, the non-owner is the attacker.
5. Final tiebreaker is random.

### Initiator Rule

- In Base Survival, the board attacker is also the battle initiator
- We do not reroll initiator based on one hero's speed

This avoids overly swingy openings caused by very high speed heroes.

### Defender Fortified Bonus

If defenders are fighting on a friendly structure node:

- all defenders gain `+15 armor`
- bonus lasts for battle turns `1` and `2`

### Ambush Bonus

If attackers entered from a node that defenders could not see on the previous board turn:

- all attackers gain `+15 speed`
- all attackers gain `+15 power`
- bonus lasts for battle turn `1`

### Fight Participants

- All living heroes on the contested node join the fight
- Adjacent heroes do not reinforce mid-fight in v1

### Fight Resolution

- Fights auto-resolve using the existing battle engine
- Survivors remain on the node
- Losers return to Fountain at `0% HP`

## Structures

### Structure Tiers

Each lane has:

- `T1`
- `T2`
- `T3` / `Base Gate`

Each side also has:

- `Fountain`
- `Core`

### Suggested HP

- `T1`: `100`
- `T2`: `140`
- `T3`: `180`
- `Core`: `260`

These are starting values for balancing and may change.

### Structure Damage

At end of turn, if a team controls an enemy structure node uncontested:

- first living allied hero on the node deals `10` structure damage
- each additional living allied hero on the same node deals `+6`

Examples:

- `1 hero`: `10`
- `2 heroes`: `16`
- `3 heroes`: `22`

### Core Damage

To damage the enemy `Core`:

- at least one enemy `T3 / Base Gate` must be controlled uncontested
- heroes on that node deal normal uncontested structure damage to the Core

## Role Traits

Traits are based on existing hero roles:

- Tank
- Bruiser
- Carry
- Nuker
- Support

These are used instead of avatar-specific traits in v1 for simplicity and readability.

### Tank

On a friendly structure node:

- all allied heroes gain `+10 armor` per Tank in the fight
- max `2` Tanks counted
- after the fight, if the node remains controlled, reduce structure damage taken there by `6` per Tank counted that turn

### Bruiser

In fights where allied hero count is less than or equal to enemy hero count:

- each Bruiser gains `+15 atk`
- each Bruiser gains `+15 power`

### Carry

On uncontested enemy structure nodes:

- each Carry deals `+8` bonus structure damage
- if that Carry survived a fight on that same node this turn, bonus becomes `+12`

### Nuker

If a Nuker moved into the contested node this turn:

- that Nuker gains `+25 power`
- bonus lasts for battle turn `1`

### Support

After winning a fight:

- all allied survivors heal `8%` max HP per surviving Support
- max `2` Supports counted

## Role Synergies

Role synergies count only the current `5` active heroes.

### Tank Synergy

- `2 Tanks`: all friendly structures gain `+15% max HP`
- `3 Tanks`: `Fortified` becomes `+25 armor` instead of `+15`

### Bruiser Synergy

- `2 Bruisers`: Bruisers gain `+10 speed` when moving into contested nodes
- `3 Bruisers`: all allies gain `+10 atk` in fights where allied hero count is less than or equal to enemy hero count

### Carry Synergy

- `2 Carries`: all allies deal `+4` structure damage on uncontested enemy nodes
- `3 Carries`: enemy Core takes `+15%` damage

### Nuker Synergy

- `2 Nukers`: `Ambush` becomes `+25 speed` and `+25 power`
- `3 Nukers`: all attackers gain `+10 power` on battle turn `1`

### Support Synergy

- `2 Supports`: Fountain heals `25%` instead of `20%`
- `3 Supports`: dead heroes respawn at Fountain with `20% HP` instead of `0%`

## Board Layout

The board is still provisional.

Current direction:

- Player side is bottom-left
- Enemy side is top-right
- There are 3 aligned lanes: top, mid, bot
- Each lane has:
  - player `T3`
  - player `T2`
  - player `T1`
  - neutral lane space
  - enemy `T1`
  - enemy `T2`
  - enemy `T3`
- Each quadrant should have jungle at its center
- Jungle should connect:
  - adjacent lanes
  - nearby tower tiers
  - river routes
- River should connect central and flank paths

### Important Map Principles

- Each connector edge equals `1` turn of movement
- Mid should be the most direct path
- Side lanes should still support rotations through jungle
- Opening teleports should only place heroes on safe friendly nodes
- Neutral and river nodes should not be available for initial placement

### Provisional Map Draft

This is the current draft map to iterate on.

Notes:

- Player side is bottom-left
- Enemy side is top-right
- Lanes are intended to be vertically aligned
- Jungle is intended to sit at the center of each quadrant
- River / neutral center sits between both sides
- This diagram is a working draft and still needs connector cleanup

```text
                                         [ETF]
                                            |
                    [ET3]-----------------[EM3]-----------------[EB3]
                      |                     |                     |
                    [ET2]------\      [EM2]      /------[EB2]
                      |         \       |       /         |
                      |          \      |      /          |
                    [ET1]------[ETQ]---[ER]---[EBQ]------[EB1]
                      |           |      |      |           |
                      |           |      |      |           |
                    [ T0 ]--------+-----[M0]----+---------[ B0 ]
                      |           |      |      |           |
                      |           |      |      |           |
                    [PT1]------[PTQ]---[PR]---[PBQ]------[PB1]
                      |          /       |       \          |
                      |         /        |        \         |
                    [PT2]------/      [PM2]      \------[PB2]
                      |                     |                     |
                    [PT3]-----------------[PM3]-----------------[PB3]
                                            |
                                         [PTF]
```

### Provisional Map Legend

- `PTF` / `ETF`: Player / Enemy Fountain
- `PT3 PM3 PB3`: Player T3 / base gate
- `PT2 PM2 PB2`: Player T2
- `PT1 PM1 PB1`: Player T1
- `ET1 EM1 EB1`: Enemy T1
- `ET2 EM2 EB2`: Enemy T2
- `ET3 EM3 EB3`: Enemy T3 / base gate
- `T0 M0 B0`: neutral lane nodes
- `PTQ PBQ`: player jungle quadrant center nodes
- `ETQ EBQ`: enemy jungle quadrant center nodes
- `PR ER`: player / enemy river entry nodes

### Provisional Map Problems Still To Solve

- The quadrant centers are closer to the intended structure now, but the ASCII still compresses some diagonal edges
- We still need an exact adjacency list derived from this layout before implementation
- We may still want one additional river-center or crossroads node if rotations feel too linear in playtests
- We need to decide whether `T0`, `M0`, and `B0` should connect to each other directly or only through quadrant / river nodes
- The current drawing is useful for discussion, but not final enough to derive exact adjacency without another pass

### Opening Placement

At match start, heroes may be placed only on:

- `Fountain`
- friendly `T3`
- friendly `T2`
- friendly `T1`

Not on:

- jungle nodes
- river nodes
- neutral nodes
- enemy-side nodes

## Current Open Questions

- Final board geometry and node naming
- Exact jungle / river connectors
- Whether mid should be shorter than top/bot or fully symmetric
- Whether fights should happen only on same-node collisions or also by adjacency on certain nodes
- Whether structure vision should extend beyond their own node
- How much speed should matter inside multi-hero fights after board attacker is chosen
- Whether the engine needs a dedicated Base Survival battle mode instead of reusing current match assumptions

## Current Direction Summary

Base Survival is currently defined as:

- a turn-based PvE macro board game
- no economy
- no farming
- no creeps in v1
- move or hold all 5 active heroes each turn
- use board positioning and information to create favorable fights
- retreat and recover through Fountain
- push structures when lanes are uncontested
- derive depth from role traits, synergies, vision, rotations, and survival timing
