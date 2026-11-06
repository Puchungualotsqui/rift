# RIFT — Game Design Bible

**Working title:** *RIFT*
**Version:** v1.1 (v1.0 with implementation clarifications)
**Status:** Core design locked. Ready for rulebook wording, component production, and playtesting.

---

## Table of Contents

1. [Design Pillars](#1-design-pillars)
2. [At a Glance](#2-at-a-glance)
3. [Core Loop & Turn Structure](#3-core-loop--turn-structure)
4. [The Map](#4-the-map)
5. [Action Economy & Resources](#5-action-economy--resources)
6. [Combat](#6-combat)
7. [Factions](#7-factions)
   - 7.1 Swarm Collective
   - 7.2 Corporate Consortium
   - 7.3 AI Network
   - 7.4 Nomad Fleet
8. [Cards & Deck Tuning](#8-cards--deck-tuning)
9. [Global Objectives](#9-global-objectives)
10. [Secret Directives](#10-secret-directives)
11. [Scoring & End Game](#11-scoring--end-game)
12. [Player Count Adjustments (2P / 3P)](#12-player-count-adjustments-2p--3p)
13. [Setup Procedure](#13-setup-procedure)
14. [Component List](#14-component-list)
15. [Design Constraints (What This Game Never Does)](#15-design-constraints-what-this-game-never-does)
16. [Open Items & Playtesting Knobs](#16-open-items--playtesting-knobs)
17. [Version History](#17-version-history)

---

## 1. Design Pillars

1. **Dual-format native.** The game must work fully as a board game *and* fully as a video game. The video game automates rules, hidden information, AI, and bookkeeping — it does not add mechanics that cannot exist on a table.
2. **Asymmetric but learnable.** Four factions, each with one unique action, one unique deck identity, one unique scoring vector, and one clear weakness. Light-medium rules, deep interaction.
3. **Deterministic.** No dice. Combat is card-modified and readable. Outcomes are calculable.
4. **Equal finish.** Fixed 6 rounds. Everyone plays the same number of turns. No early end trigger, no elimination, no random game length.
5. **Euro backbone, thematic skin.** Public objectives, public VP track, deterministic combat, hidden hands and secret directives. Tension comes from timing and information, not from swingy randomness.
6. **Board-game friendly setup.** Terrain is dealt randomly, never placed by players. No card passing, no drafting, no tile-laying.

**Explicitly excluded mechanics (permanent):**
- Card passing / drafting / trading (7 Wonders style)
- Player-placed terrain tiles
- Dice
- Early game-end triggers
- Player elimination
- Card text that changes by player count

---

## 2. At a Glance

| | |
|---|---|
| **Players** | 2–4 |
| **Type** | Competitive asymmetric area control / engine building |
| **Length** | 6 rounds, ~90–120 min |
| **Complexity** | Light-medium |
| **Theme** | Sci-fi |
| **Map** | Fixed 19-hex board |
| **Resources** | Energy, Data (2 types) |
| **Actions** | 3 AP per turn |
| **Combat** | Deterministic, max 1 card revealed per Strike |
| **Hidden info** | Hands of cards, Secret Directives |
| **Public info** | All 6 Global Objectives, VP track |
| **Win condition** | Highest total VP after Round 6 |

---

## 3. Core Loop & Turn Structure

### Round structure
1. **Reveal/confirm** the round's Global Objective (all 6 are face-up from setup; the current round's objective is the one being scored).
2. Each player takes **one turn**, starting with the first player and proceeding clockwise.
3. After all players have taken their turn, **score the Global Objective** for that round.
4. **Rotate the first-player marker clockwise.**
5. After the Round 6 objective is scored, the game ends. Proceed to final scoring.

### Player turn structure
1. **Refresh:** gain income, draw 1 card, refresh faction abilities.
2. **Take 3 Action Points (AP).** AP cannot be banked.
3. **End turn.**

### Income (start of your turn)
- Gain **1 Energy + 1 Data** baseline.
- Gain **+1 Energy per controlled Energy Node**.
- Gain **+1 Data per controlled Data Node**.
- Draw **1 card** (hand max 5).
- Resource cap: **8 Energy, 8 Data**.

---

## 4. The Map

### Board
- **Fixed 19-hex board:** center + 2 rings (1 + 6 + 12).
- **4 marked start hexes**, roughly cardinal, on the outer ring.
- Start hexes are always **Open** terrain and never receive a terrain token.
- Use axial coordinates `(q, r)` with the center at `(0, 0)`. The four potential starts are `(-2, 0)`, `(0, -2)`, `(2, 0)`, and `(0, 2)`.

### Active hexes by player count

| Players | Active hexes | Rift tokens | Notes |
|---|---:|---:|---|
| 4 | 19 | 0 | All hexes active |
| 3 | 16 | 3 | 3 start hexes used; 4th start hex is neutral Open, empty, and active |
| 2 | 13 | 6 | Opposite start hexes; tighter map |

### Terrain types

| Terrain | Effect |
|---|---|
| **Open** | No bonus |
| **Cover** | +1 defense |
| **Energy Node** | Harvest source for Energy |
| **Data Node** | Harvest source for Data |

- Terrain is **dealt randomly** at setup from a 15-token pool.
- Players never place terrain.
- Terrain may be changed by card effects (e.g., AI Network's *Compile*).

### Rift hexes
- Impassable. Cannot be entered, controlled, or scored.
- Placed at setup per player count. Never placed on a start hex chosen for a player; in 2P the two unused potential starts are Rifts.
- Select remaining Rift hexes from the outer ring excluding all four potential starts. Rank each candidate by its distance to the **nearest** chosen start, farthest first; break ties by ascending `q`, then ascending `r`. Hex distance is `(abs(dq) + abs(dr) + abs(dq + dr)) / 2`.

### Hex capacity
- Max **3 units** and **1 structure** per hex.
- Relays (AI Network only) coexist with units/structures — max 1 relay per hex.
- A hex is **controlled** by a player if that player has at least one unit or structure there and no enemy units or structures.
- **Relays count as control markers for AI Network only.** Relays do not block other factions' control.
- Enemy units block entry; you must Strike to clear or capture.

---

## 5. Action Economy & Resources

### Resources
- **Energy** — used for units, faction actions, and some effects.
- **Data** — used for structures, cards, and some effects.
- Cap: **8 Energy, 8 Data** per player.

### Core actions (1 AP each)

| Action | Cost | Effect |
|---|---|---|
| **Move** | 1 AP | Move up to 2 units from one hex to an adjacent hex. Cannot enter an enemy-occupied hex. |
| **Harvest** | 1 AP | Choose a controlled node hex: gain 2 of that node's resource. *(Unavailable to Nomad Fleet.)* |
| **Build Unit** | 1 AP + 1 Energy | Place 1 unit on a controlled hex with unit space. *(Corp and AI pay their faction cost instead — see factions.)* |
| **Build Structure** | 1 AP + 2 Data | Place 1 structure on a controlled hex with no structure. *(Unavailable to Swarm Collective.)* |
| **Strike** | 1 AP | Attack an adjacent enemy-occupied hex. May reveal 1 card from hand for combat. |
| **Protocol** | 1 AP + card's Data cost | Play a card from hand for its non-combat effect. |
| **Faction Action** | 1 AP + listed cost | Unique to your faction. |

### Cards
- Personal faction decks only. **No passing, no trading, no drafting.**
- Hand max **5**. Draw 1 at start of turn.
- Cards are played either as **Protocol actions** or **revealed during a Strike**.
- Combat cards cannot be played as Protocol actions, and vice versa.
- For a Protocol that reveals a hand or deck cards, pay and discard the Protocol before looking. If the effect requires a choice after looking, finish that choice before taking another action or ending the turn.

### Combat card reveal cost
- Revealing a card during a Strike costs its **Data cost on top of** the 1 AP for Strike.
- **Maximum 1 card revealed per Strike.**
- You must be able to pay the Data cost.

---

## 6. Combat

Combat is **deterministic** and **card-modified**.

### Procedure
1. Attacker declares a Strike against an adjacent enemy-occupied hex (1 AP).
2. At most **1 combat card total** is revealed, paying its Data cost. Either side may select one. If both select a card, the attacker's card is revealed and the defender's is not, unless the defender selects *Counter-Intelligence*: then only *Counter-Intelligence* is revealed and the attacker's card is not. A card that is not revealed is neither paid for nor discarded.
3. Calculate strength:
   - **Attacker strength** = number of attacking units + card bonus + faction modifiers.
   - **Defender strength** = number of defending units + terrain defense (Cover +1) + structure defense (+1 if a structure is present) + card bonus + faction modifiers.
4. Compare:
   - Higher strength wins.
   - **Ties go to the defender.**
   - The loser removes **1 unit**.
5. If the defender loses their last unit, the attacker may move 1 unit into the hex and destroy any structure there.

### Modifiers summary

| Source | Effect |
|---|---|
| Units | 1 strength each |
| Cover terrain | +1 defender defense |
| Structure in hex | +1 defender defense |
| Relays adjacent (AI Network) | +1 defense to adjacent friendly hexes |
| Combat cards | As printed |
| Faction modifiers | As printed |

**No dice. Ever.**

---

## 7. Factions

### Overview

| | **Swarm Collective** | **Corporate Consortium** | **AI Network** | **Nomad Fleet** |
|---|---|---|---|---|
| **Identity** | Hive-mind replication | Industrial engine | Distributed intelligence | Raider nomads |
| **Unique action** | Proliferate | Reinvest | Rewire | Hit and Run |
| **Scoring** | Board width (units + hexes) | Structures + stored resources | Relay network | Destruction + theft + directives |
| **Weakness** | No structures; weak cards | Expensive units; static | Fragile units; slow setup | Can't harvest; poor defense |
| **Resource lean** | Energy | Data | Data | Both (stolen) |
| **Playstyle** | Spread and overwhelm | Build tall and defend | Connect and manipulate | Harass and disrupt |
| **Deck size** | 12 | 14 | 13 | 12 |

---

### 7.1 Swarm Collective — *"The Chorus"*

**Theme:** A hive intelligence that replicates across the map. Individual units are mindless; the Chorus is everywhere.

#### Unique action — Proliferate *(1 AP + 1 Energy)*
Place 1 unit on each of up to 2 controlled hexes (one unit per hex). Rewards spreading wide.

#### Deck — "Hive" (12 cards)

**Combat cards (revealed during Strike):**

| # | Card | Cost | Effect |
|---|---|---|---|
| 1 | **Overwhelm** | 0 Data | +1 strength per unit in the hex beyond the first (max +2). |
| 2 | **Chitin** | 0 Data | +2 defense this combat. |
| 3 | **Rush** | 1 Data | +2 strength if you have more units in the combat than the defender. |
| 4 | **Frenzy** | 1 Data | If you win this combat, each surviving attacker may move 1 hex. |

**Protocol cards (1 AP + Data cost):**

| # | Card | Cost | Effect |
|---|---|---|---|
| 5 | **Sacrifice** | 0 Data | Destroy 1 of your units. Draw 2 cards. |
| 6 | **Swarm Sense** | 0 Data | Look at top 2 cards of your deck. Draw 1, put the other on the bottom. |
| 7 | **Burrow** | 1 Data | Move 1 unit to an adjacent hex, ignoring enemy units (must end in a hex without enemy units). |
| 8 | **Replicate** | 1 Data | Place 1 unit on a hex you control. |
| 9 | **Hive Mind** | 1 Data | All your units in one hex gain +1 strength until end of turn. |
| 10 | **Corrode** | 2 Data | Destroy 1 enemy structure or relay in a hex adjacent to one of your units. |
| 11 | **Brood** | 2 Data | Place 2 units, each on a different controlled hex. |
| 12 | **Endless** | 0 Data | Gain 2 Energy. |

**Cost distribution:** 0 Data × 5, 1 Data × 5, 2 Data × 2 → avg **0.75 Data**.

#### Scoring
`floor(total units on board / 2) + controlled hexes`
*Expected range: ~8–14 VP.*

#### Weakness
- **Cannot build structures** (Build Structure unavailable).
- Individual units are strength 1.
- Vulnerable to multi-unit destruction and hex cutoffs.
- Poor individual card quality; relies on quantity and synergy.

#### Starting setup
- **Forces:** 3 units on start hex.
- **Resources:** 2 Energy, 1 Data.
- **Hand:** 3 cards.

#### Playstyle
Expand aggressively, contest every hex, drown opponents in bodies. Use *Sacrifice* for tempo and card draw. Win by being everywhere at once.

---

### 7.2 Corporate Consortium — *"Helix Industries"*

**Theme:** A megacorp that terraforms and industrializes. Their board presence is concrete and steel, not flesh.

#### Unique action — Reinvest *(1 AP)*
Gain **1 Energy and 1 Data for each structure you control** (max 3 structures → 3 Energy + 3 Data). Rewards building up.

#### Faction cost modifier
- **Build Unit costs 2 Energy** (instead of 1).

#### Deck — "Corporate" (14 cards)

**Combat cards:**

| # | Card | Cost | Effect |
|---|---|---|---|
| 1 | **Ablative Plating** | 1 Data | +2 defense. +3 instead if the defending hex contains your structure. |
| 2 | **Security Detail** | 1 Data | +1 strength for each structure you control adjacent to the combat hex (max +2). |
| 3 | **Counter-Intelligence** | 0 Data | The attacker cannot reveal a combat card this combat. |

**Protocol cards:**

| # | Card | Cost | Effect |
|---|---|---|---|
| 4 | **Hostile Takeover** | 2 Data | Steal 1 resource (Energy or Data) from an opponent. |
| 5 | **Fortify** | 1 Data | A structure you control gains +2 defense until the start of your next turn. |
| 6 | **Dividend** | 0 Data | Gain 1 Data for each structure you control (max 3). |
| 7 | **Lobby** | 1 Data | Draw 2 cards. |
| 8 | **Redundancy** | 2 Data | Place a shield token on a structure you control. The next time that structure would be destroyed, remove the shield instead. Max 1 shield per structure. |
| 9 | **Bailout** | 0 Data | Gain 2 Data. |
| 10 | **Contract** | 1 Data | Choose a resource node you control. Gain 3 of that node's resource. |
| 11 | **Automate** | 1 Data | Your next Build Unit or Build Structure action this turn costs 0 resources. |
| 12 | **Audit** | 1 Data | Look at an opponent's hand. That player discards 1 card of your choice. |
| 13 | **Shareholder Value** | 1 Data | Draw 1 card and gain 1 Data. |
| 14 | **Monopoly** | 2 Data | Choose a resource type. Each opponent loses 1 of that resource. You gain 1 of that type per opponent affected. |

**Cost distribution:** 0 Data × 3, 1 Data × 8, 2 Data × 3 → avg **1.00 Data**.

#### Scoring
`2 VP per structure + floor((Energy + Data) / 3)`
*Expected range: ~8–14 VP.*

#### Weakness
- **Units cost 2 Energy.**
- Structures are static; losing them costs VP and engine.
- Slow start; needs 2–3 rounds to come online.
- Few units on board; vulnerable to early aggression.

#### Starting setup
- **Forces:** 1 structure + 2 units on start hex.
- **Resources:** 2 Energy, 2 Data.
- **Hand:** 3 cards.

#### Playstyle
Build tall, defend investments, generate resources. Use *Fortify* and *Redundancy* to protect structures. Win through economic dominance and a fortified position.

---

### 7.3 AI Network — *"The Lattice"*

**Theme:** A distributed machine intelligence that exists across relay nodes. Its body is the network itself.

#### Unique action — Rewire *(1 AP + 1 Data)*
Choose one:
- Place a **relay token** on a hex you control (max 1 relay per hex).
- **Change the terrain** of a hex you control to any terrain type.

#### Faction cost modifier
- **Build Unit costs 2 Data** (instead of 1). Units are strength 1.

#### Relay rules
- Relays are a third token type (not units, not structures). They coexist with units/structures — max 1 relay per hex.
- Relays give **+1 defense to adjacent friendly hexes**.
- Relays count as controlled hexes for scoring and objectives.
- An enemy unit in a hex with a relay may destroy the relay as a free action once per turn (no AP cost).

#### Deck — "Network" (13 cards)

**Combat cards:**

| # | Card | Cost | Effect |
|---|---|---|---|
| 1 | **Firewall** | 1 Data | +2 defense. +3 instead if a relay you control is adjacent to the defending hex. |
| 2 | **Feedback Loop** | 1 Data | +1 strength for each relay adjacent to the combat hex (max +2). |
| 3 | **Ghost Protocol** | 0 Data | +1 defense. If you lose this combat, move 1 surviving unit to an adjacent hex. |

**Protocol cards:**

| # | Card | Cost | Effect |
|---|---|---|---|
| 4 | **Data Spike** | 1 Data | Look at an opponent's hand. |
| 5 | **Reroute** | 1 Data | Move 1 relay you control to an adjacent hex you control. |
| 6 | **Cascade** | 0 Data | Draw 1 card for each relay you control (max 2). |
| 7 | **Override** | 2 Data | Target opponent discards 1 card at random. |
| 8 | **Ping** | 0 Data | Look at the top card of your deck. You may put it on the bottom. Draw 1 card. |
| 9 | **Mesh** | 1 Data | Place 1 relay on a hex you control that doesn't have a relay. |
| 10 | **Relay Shield** | 1 Data | Until your next turn, your relays cannot be destroyed by enemy units. (Card effects still work.) |
| 11 | **Fork** | 1 Data | Choose a hex you control. Gain 1 Energy or 1 Data for each relay adjacent to that hex (max 2). |
| 12 | **Compile** | 2 Data | Change the terrain of a hex you control to any terrain type. If you change it to a node type, gain 1 of that resource. |
| 13 | **Pulse** | 0 Data | Your relays give +1 defense until end of turn. |

**Cost distribution:** 0 Data × 4, 1 Data × 7, 2 Data × 2 → avg **0.85 Data**.

#### Scoring
`1 VP per relay + 2 VP if you have a connected relay network of 3+ + 2 VP if you have a connected relay network of 5+`
*Expected range: ~8–14 VP.*

#### Weakness
- **Units cost 2 Data** and are strength 1.
- Relays are vulnerable to enemy units.
- Slow setup; needs relays before network scoring kicks in.
- Poor at direct combat; relies on positioning and disruption.

#### Starting setup
- **Forces:** 1 relay + 1 unit on start hex.
- **Resources:** 2 Energy, 2 Data.
- **Hand:** 3 cards.

#### Playstyle
Spread relays, connect your network, manipulate terrain and hands. Win through board control and information advantage. Avoid direct fights; outmaneuver.

---

### 7.4 Nomad Fleet — *"The Drift"*

**Theme:** A fleet of raiders who never settle. They take what they need and move on.

#### Unique action — Hit and Run *(1 AP)*
Move up to 2 units to an adjacent hex. As an exception to ordinary movement, this action may enter an enemy-controlled hex if its unit capacity permits. You may immediately make a **free Strike** against that hex if it contains enemy units or a structure (this Strike does not cost AP). The move happens before combat; units may remain together in the hex if the Strike is declined or does not clear it.

#### Faction restrictions
- **Cannot Harvest** (Harvest action unavailable).
- **Cannot build structures on nodes** (structures may only be built on Open/Cover hexes).

#### Deck — "Raider" (12 cards)

**Combat cards:**

| # | Card | Cost | Effect |
|---|---|---|---|
| 1 | **Boarding Party** | 1 Data | +1 strength for each unit you have in the attacking hex. |
| 2 | **Evasive Maneuvers** | 0 Data | +2 defense this combat. |
| 3 | **Ambush** | 1 Data | +2 strength if the defender has a structure or relay in the hex. |
| 4 | **Smoke Screen** | 1 Data | After combat (win or lose), move 1 surviving unit to an adjacent hex. |
| 5 | **Plunder** | 1 Data | If you win this combat, gain 1 Energy or 1 Data from the defender. |

**Protocol cards:**

| # | Card | Cost | Effect |
|---|---|---|---|
| 6 | **Scorched Earth** | 1 Data | Destroy 1 structure or relay you control. Gain 3 Energy. |
| 7 | **Smoke and Mirrors** | 0 Data | Draw 1 card. |
| 8 | **Forage** | 1 Data | Gain 1 Energy and 1 Data. |
| 9 | **Strike Team** | 1 Data | Move 1 unit to an adjacent hex. If that hex contains an enemy structure or relay, you may destroy it (no combat needed). |
| 10 | **Flee** | 0 Data | Move 1 unit from a hex containing enemy units to an adjacent hex (disengage without combat). |
| 11 | **Tribute** | 2 Data | Choose an opponent. They give you 1 resource of their choice. You gain 1 additional resource of the same type. |
| 12 | **Warpath** | 2 Data | This turn, your first Strike costs 0 AP. Your units may move through hexes containing enemy units this turn (they still cannot end there). |

- **Strike Team** may enter an adjacent hex containing an enemy structure but no enemy units; destruction is optional. If a shield absorbs the destruction attempt, the unit still moves and the structure remains.
- **Warpath movement:** one Move action may move up to 2 units across an enemy-unit hex to a second adjacent hex. The intermediate and destination hexes cannot be Rifts; the destination must have capacity and no enemy units or structures.

**Cost distribution:** 0 Data × 3, 1 Data × 7, 2 Data × 2 → avg **0.92 Data**.

#### Scoring
`1 VP per enemy unit destroyed + 1 VP per enemy structure destroyed + floor(stolen resources / 3)`
*Expected range: ~8–14 VP.*

#### Weakness
- **Cannot Harvest.** Must steal or use cards.
- Poor defense; units strength 1; structures cost 3 Energy (rarely built).
- Static positions are death.
- Theft is weaker in low player counts (see 2P adjustments).

#### Starting setup
- **Forces:** 2 units on start hex.
- **Resources:** 1 Energy, 1 Data.
- **Hand:** 3 cards.

#### Playstyle
Harass, raid, steal, hit and run. Target weak spots, avoid fair fights, win by disruption and directive completion. The map is your resource.

---

## 8. Cards & Deck Tuning

### Card economy targets

| Budget | Value |
|---|---|
| AP per game | 18 |
| Expected AP on card plays | 5–7 |
| Expected cards seen | 10–12 |
| Expected cards played | 7–9 |
| Data income per game (non-Nomad) | 12–16 |
| Data income per game (Nomad) | 8–12 |
| Target avg Data cost per card | 0.8–1.2 |
| Max deck size | 14 |

### Deck composition summary

| Faction | Cards | Combat | Protocol | 0 Data | 1 Data | 2 Data | Avg cost |
|---|---:|---:|---:|---:|---:|---:|---:|
| Swarm | 12 | 4 | 8 | 5 | 5 | 2 | 0.75 |
| Corp | 14 | 3 | 11 | 3 | 8 | 3 | 1.00 |
| AI | 13 | 3 | 10 | 4 | 7 | 2 | 0.85 |
| Nomad | 12 | 5 | 7 | 3 | 7 | 2 | 0.92 |

**Deck size asymmetry rationale:**
- **Corp** (14): most draw effects; longer game plan.
- **AI** (13): wants specific cards (relays) but needs card flow.
- **Swarm / Nomad** (12): consistency and tempo; lean decks.

### Card rules recap
- **Max 1 card revealed per Strike**, paying its Data cost on top of 1 AP.
- Combat cards cannot be played as Protocol actions; Protocol cards cannot be revealed in combat.
- No card creates an infinite loop or free card advantage at 0 Data (verified).
- No card text changes at any player count.

---

## 9. Global Objectives

**All 6 are laid out face-up at setup, in fixed round order.** Everyone sees them from the start. Hidden information lives in hands and Secret Directives, not the objective row.

**Scoring:** Checked at the end of the specified round. Every player who meets the condition scores **2 VP**. Objectives are **not first-come**; multiple players can score. VP is tracked immediately on the VP track.

| Round | Objective | Condition (end of round) | Design intent |
|---|---|---|---|
| **1** | **Pioneer** | Control 2+ hexes. | Gets everyone moving. |
| **2** | **Stockpile** | Have 5+ combined Energy + Data. | Spend-or-save tension. |
| **3** | **Develop** | Control 2+ hexes containing a structure, relay, or resource node. | Rewards infrastructure; faction-flexible. |
| **4** | **Engage** | Win at least 1 combat this round. | Forces interaction. |
| **5** | **Mobilize** | Have 4+ units on the board. | Rewards military investment. |
| **6** | **Dominate** | Control 4+ hexes (**3+ in 2-player games**). | Hard finale. |

**Why fixed order, not shuffled:** light-medium players can plan a 6-round arc. Shuffling risks hard objectives early and easy ones late, which feels arbitrary. (A future expansion could add an objective-pool draft, but not in v1.)

**Max public VP: 12 per player.**

---

## 10. Secret Directives

- **Deck:** 12 unique cards, shuffled at setup.
- **Draw:** Each player draws **2** face-down at setup. **Nomad Fleet draws 3.**
- **Visibility:** Hidden until final scoring. No mid-game reveal, no trading, no redraw.
- **Scoring:** Each completed directive = **2 VP** at final scoring. Uncompleted = 0.

| # | Directive | Condition (checked at final scoring) |
|---|---|---|
| 1 | **Warlord** | Win 3+ combats over the course of the game. |
| 2 | **Assassin** | Destroy 3+ enemy units over the course of the game. |
| 3 | **Saboteur** | Destroy 2+ enemy tokens (units, structures, or relays). |
| 4 | **Conqueror** | Control 5+ hexes at game end. |
| 5 | **Hoarder** | End the game with 6+ combined resources. |
| 6 | **Architect** | Control 2+ hexes containing a structure, relay, or resource node at game end. |
| 7 | **Collector** | Control 2+ resource nodes at game end. |
| 8 | **Survivor** | End the game with 5+ units on the board. |
| 9 | **Tactician** | Play 6+ cards over the course of the game. |
| 10 | **Expansionist** | Control at least 1 hex in the inner ring and 1 hex in the outer ring at game end. |
| 11 | **Opportunist** | Score 3+ Global Objectives over the course of the game. |
| 12 | **Vanguard** | Control the center hex at game end. |

**Design checks:**
- Every directive is achievable by every faction.
- No contradictory pairs; any 2–3 draw is internally consistent.
- Faction lean is variance, not impossibility.
- Tracking needs only 5 counters: combat wins, units destroyed, tokens destroyed, cards played, objectives scored.

**Max directive VP: 4 (Nomad: 6).**

---

## 11. Scoring & End Game

### End-game trigger — locked
**The game lasts exactly 6 rounds.** No VP threshold ends the game early. No player can trigger the end alone. Everyone finishes at the same time. Each player gets **18 AP** per game (6 turns × 3 AP).

### Scoring sources

| Source | Max VP | Timing |
|---|---:|---|
| Global Objectives (6 × 2 VP) | 12 | End of each round, on VP track |
| Faction VP | ~8–14 (uncapped formula) | Final scoring only |
| Secret Directives (2–3 × 2 VP) | 4 (Nomad: 6) | Final scoring only |
| **Theoretical max** | **~32** | — |
| **Typical winning score** | **22–26** | — |

### Faction scoring formulas (standard)

| Faction | Formula |
|---|---|
| **Swarm** | `floor(units on board / 2) + controlled hexes` |
| **Corp** | `2 VP per structure + floor((Energy + Data) / 3)` |
| **AI** | `1 VP per relay + 2 VP if connected network of 3+ + 2 VP if connected network of 5+` |
| **Nomad** | `1 VP per enemy unit destroyed + 1 VP per enemy structure destroyed + floor(stolen resources / 3)` |

### Final scoring sequence
1. Score the Round 6 Global Objective.
2. **Reveal all Secret Directives.**
3. **Calculate Faction VP** for each player.
4. **Add Public Objective VP** already on the track.
5. **Add Secret Directive VP.**
6. Highest total VP wins.

### Tiebreakers (in order)
1. Most Public Objective VP.
2. Most completed Secret Directives.
3. Most Faction VP.
4. Most resources remaining (Energy + Data).
5. Shared victory.

---

## 12. Player Count Adjustments (2P / 3P)

**Guiding rule:** adjustments are **setup-level or scoring-reference-level only**. No card text changes at any player count. Everything fits on one double-sided reference card.

### 3-Player
1. **Map:** 16 active hexes. Place **3 Rift tokens** on the outer non-start hexes farthest from the nearest of the three chosen start hexes, using the Rift selection rule in Section 4.
2. **The 4th start hex** is **neutral Open terrain, starts empty**, and is a normal active hex (can be moved into, controlled, and scored).
3. All other rules, cards, faction formulas, objectives, and costs are unchanged.
4. First player chosen randomly; marker rotates clockwise each round.

### 2-Player

**Map:**
1. **13 active hexes.** Place **6 Rift tokens** using the Rift selection rule in Section 4.
2. **Opposite start hexes** are used. The other two potential start hexes are Rifts; select the remaining four Rifts from outer non-start hexes.
3. No neutral start hex in 2P.

**Global objective:**
- **Dominate (Round 6):** control **3+ hexes** instead of 4+. All other objectives unchanged.

**Scoring reference card (2P side):**

| Faction | Standard formula | 2P formula |
|---|---|---|
| **Swarm** | `floor(units / 2) + controlled hexes` | `floor(units / 3) + controlled hexes` |
| **Corp** | `2 VP/structure + floor((Energy+Data) / 3)` | `2 VP/structure + floor((Energy+Data) / 4)` |
| **AI** | `1 VP/relay + 2 VP at 3+ connected + 2 VP at 5+ connected` | `1 VP/relay + 2 VP at 4+ connected + 2 VP at 6+ connected` |
| **Nomad** | `... + floor(stolen / 3)` | `... + floor(stolen / 2)` |

**Nomad still draws 3 Secret Directives in 2P.**

**Rationale (for the rulebook):**
- **Swarm:** more space per player; `/3` tempers easy spreading.
- **Corp:** fewer opponents = safer structures and easier hoarding; `/4` tempers resource VP.
- **AI:** more space = easier networks; higher thresholds preserve difficulty.
- **Nomad:** one opponent = fewer total stealable resources; `/2` compensates.

**Everything else unchanged:** no card text changes; no changes to AP, costs, income, combat, hand size, deck sizes, starting setup, or other objectives. First player random; marker rotates clockwise each round.

### 2P pairing guidance (not a rule)
Recommended first-game pairings: **Swarm vs Corp** (width vs height), **AI vs Nomad** (network vs raid). All pairings are viable.

---

## 13. Setup Procedure

### Components used
- Hex board
- Rift tokens (0 / 3 / 6 by player count)
- 15 terrain tokens: **4 Energy Node, 4 Data Node, 4 Cover, 3 Open**
- 6 Global Objective cards
- 12 Secret Directive cards
- 4 faction sets
- First-player marker
- Reference card

### Steps

**Step 1 — Choose players and factions**
- Choose 2, 3, or 4 players.
- Each player selects a faction.
- If two players want the same faction, shuffle those faction tokens and assign randomly; the other player chooses again.
- Each player takes their faction board, deck, and tokens.

**Step 2 — Place board and Rift tokens**
- Place the 19-hex board centrally. Select the set of potential start hexes to be used before placing Rifts: all four in 4P, three in 3P, or an opposite pair in 2P. Players choose among that set in Step 7.
- Place Rift tokens using Section 4's distance and tie-break rule:
  - 4P: 0 Rifts.
  - 3P: 3 Rifts on outer non-start hexes; the unused fourth start remains active.
  - 2P: 6 Rifts: the two unused potential starts and four outer non-start hexes.
- Never place a Rift on a start hex chosen for a player.

**Step 3 — Deal terrain**
- Shuffle the 15 terrain tokens face-down.
- Deal one terrain token face-up to each **active non-start hex**:
  - 4P: 15 hexes → deal 15
  - 3P: 12 hexes → deal 12; return 3 to box
  - 2P: 11 hexes → deal 11; return 4 to box
- Start hexes remain **Open** and receive no terrain token.
- In 3P, the unused 4th start hex is neutral Open, empty, active, and receives no terrain token.
- Players do not choose or place terrain.

**Step 4 — Place Global Objectives**
- Lay out the 6 Global Objective cards face-up in round order:
  **1 Pioneer → 2 Stockpile → 3 Develop → 4 Engage → 5 Mobilize → 6 Dominate.**

**Step 5 — Deal Secret Directives**
- Shuffle the 12 Secret Directives.
- Deal **2 face-down** to each player. **Nomad receives 3.**
- Keep hidden until final scoring. No redraws, no trading.

**Step 6 — Determine first player**
- Shuffle the chosen faction tokens; draw one at random.
- That token's owner is the **first player**. Place the marker.

**Step 7 — Choose start hexes and place starting forces**
- Starting with the first player and proceeding clockwise, each player chooses one available start hex:
  - 4P: all 4 available.
  - 3P: 3 available; the 4th is neutral Open and empty.
  - 2P: two opposite start hexes; first player chooses one, second gets the other.
- Place starting forces/resources per faction:

| Faction | Starting forces | Starting resources | Starting hand |
|---|---|---|---:|
| **Swarm** | 3 units | 2 Energy, 1 Data | 3 |
| **Corp** | 1 structure + 2 units | 2 Energy, 2 Data | 3 |
| **AI** | 1 relay + 1 unit | 2 Energy, 2 Data | 3 |
| **Nomad** | 2 units | 1 Energy, 1 Data | 3 |

- Shuffle your faction deck; draw 3 cards as your starting hand.

**Step 8 — Begin play**
- Round 1 begins with the first player's turn.
- Round 1 Global Objective is **Pioneer**.
- After all players have taken a turn, score Pioneer, rotate the first-player marker clockwise, and begin Round 2.

### Setup checklist
1. Choose 2–4 players and factions.
2. Place board; place 0/3/6 Rift tokens per reference card.
3. Shuffle 15 terrain tokens; deal face-up to active non-start hexes; starts stay Open.
4. Lay out 6 Global Objectives face-up in round order.
5. Shuffle 12 Secret Directives; deal 2 each (Nomad 3), hidden.
6. Draw a faction token at random → first player.
7. In clockwise order from first player, choose start hexes and place starting forces/resources; draw 3 cards.
8. Begin Round 1 with Pioneer.

---

## 14. Component List

| Component | Count | Notes |
|---|---:|---|
| Hex board | 1 | 19 hexes; 4 marked start hexes |
| Terrain tokens | 15 | 4 Energy Node, 4 Data Node, 4 Cover, 3 Open |
| Rift tokens | 6 | 0 / 3 / 6 by player count |
| Global Objective cards | 6 | Face-up in round order |
| Secret Directive cards | 12 | Shuffled, dealt hidden |
| Faction decks | 4 | Swarm 12, Corp 14, AI 13, Nomad 12 (total 51) |
| Faction boards | 4 | Resource tracks, directive slots, tracking counters |
| Faction action boards | 4 | One per faction |
| Player boards | 4 | Resource tracks, directive slots, tracking counters |
| Tracking counters | ~5 per player | Combat wins, units destroyed, tokens destroyed, cards played, objectives scored |
| Unit tokens | ~40 | Faction-colored |
| Structure tokens | ~12 | Faction-colored |
| Relay tokens | ~8 | AI Network only |
| Shield tokens | ~4 | Corp *Redundancy* |
| Resource tokens | ~40 | Energy and Data |
| VP track | 1 | 0–40 range |
| First-player marker | 1 | — |
| Reference card | 1 | Double-sided: 3P / 2P adjustments |
| Rulebook | 1 | — |

---

## 15. Design Constraints (What This Game Never Does)

These are permanent design constraints. Any future card, faction, or expansion must respect them.

1. **No card passing, drafting, or trading.**
2. **No player-placed terrain tiles.** Terrain is dealt randomly at setup.
3. **No dice.**
4. **No early game-end trigger.** Fixed 6 rounds.
5. **No player elimination.**
6. **No card text that changes by player count.** Player-count adjustments are setup-level or scoring-reference-level only.
7. **The video game never adds a mechanic that cannot exist on a table.** It only automates setup, hidden info, AI, bookkeeping, and feedback.
8. **No infinite loops or free card advantage at 0 Data.** Verified in v0.7.
9. **Combat reveals max 1 card per Strike.** Deterministic outcomes only.
10. **All 6 Global Objectives are public from setup.** Hidden info lives in hands and Secret Directives.

---

## 16. Open Items & Playtesting Knobs

These are **tuning knobs, not rule changes**. First things to adjust if playtesting shows problems.

### Card / faction balance
1. **Nomad starting resources** (1 Energy, 1 Data) may be too tight → try 2 Energy, 1 Data.
2. **Swarm Corrode** at 2 Data may be too expensive → try 1 Data.
3. **Corp Redundancy** at 2 Data + shield may be too strong vs. Nomad → monitor.
4. **Nomad Warpath** at 2 Data is the biggest tempo swing → monitor.
5. **Corp Counter-Intelligence** at 0 Data may be auto-include → monitor.
6. **AI Compile** terrain change may enable combos → monitor.
7. **Deck sizes** (12/14/13/12) may need evening if draw consistency is a problem.
8. **Combat card cap (1 per Strike)** is locked; if combat feels flat, consider 2 reveals at higher cost.

### 2P / 3P balance
9. **Swarm 2P divisor** — if Swarm dominates 2P, try `/4` or cap unit VP at 4.
10. **Corp 2P divisor** — if Corp hoards too easily, try `/5`.
11. **AI 2P thresholds** — if 4+/6+ is too harsh, revert to 3+/5+ but cap network VP at 2 total.
12. **Nomad 2P theft divisor** — if `/2` is too generous, revert to `/3` and give Nomad +1 starting Energy.
13. **3P neutral start hex** — if it becomes kingmaker, consider making it Cover instead of Open.

### Remaining production work (not design)
- Rulebook wording and layout
- Reference card layout (3P / 2P sides)
- Art direction (sci-fi, readable iconography, minimal art dependency)
- Digital implementation spec (automation of objectives, directives, VP projection, AI)
- Playtest schedule and balance passes

---

## 17. Version History

| Version | Locked content |
|---|---|
| **v0.1** | Design spine: competitive, 2–4P, light-medium, sci-fi, hexes, hidden info, deterministic card combat, asymmetric factions |
| **v0.2** | Core loop, shared actions, 3 AP, 2 resources (Energy/Data), deterministic combat, 4 faction archetypes |
| **v0.3** | Map size (19 hexes, 4 terrain types, capacity 3 units + 1 structure), full action economy, income, resource caps |
| **v0.4** | Four full faction kits: unique actions, deck identities, scoring vectors, weaknesses, starting setups, interaction matrix |
| **v0.5** | End-game trigger (fixed 6 rounds), three-part scoring, final scoring sequence, tiebreakers |
| **v0.6** | Six Global Objectives (fixed order), 12 Secret Directives, scoring summary, component check |
| **v0.7** | Full card lists for all four factions (51 cards total), card costs, deck tuning, economy verification |
| **v0.8** | 2P / 3P adjustments: Rift tokens, neutral start hex, Dominate threshold, 2P scoring reference card |
| **v0.9** | Full setup procedure, terrain token pool, setup checklist |
| **v1.0** | This document: consolidated design bible |
| **v1.1** | Clarified Rift selection, the one-card combat cap, informational card timing, Nomad movement exceptions, and deck cost summaries |

---

*End of RIFT Game Design Bible v1.1.*
