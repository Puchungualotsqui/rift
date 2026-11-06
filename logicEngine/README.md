# RIFT logic engine

This directory contains the headless Odin rules engine for [RIFT](../DESIGN.md): a six-round, 2–4 player game on a radius-two, 19-hex board. Setup, turns, faction actions, Protocol and Combat card effects, objectives, and final scoring are integrated in the logic package. The rule clarifications used by the engine are recorded in `DESIGN.md` v1.1. This package provides pure game logic, not a UI, networking, persistence, or a standalone game executable.

`DESIGN.md` describes the intended game. Where it is ambiguous or differs from the code, this README describes the current implementation, not a resolution of the design.

## Architecture and state

All source files belong to the `logicEngine` package. The caller owns a `Game` and passes a pointer to procedures that inspect or mutate it. Player indices are zero-based and run clockwise; `Hex{q, r}` uses axial coordinates. State uses fixed-size arrays for the board, players, decks, hands, and directives. A hex holds at most `UNIT_CAP` (3) units in total, and resources are capped at `RESOURCE_CAP` (8).

- `core.odin`: state, constants, hex geometry, and control. An AI relay grants its owner control even when an opponent also controls the same hex.
- `setup.odin` and `shuffle.odin`: select Rifts, prepare reproducible setup orders, create the board and players, and deal cards and directives.
- `turns.odin`: income, drawing, payment, turn phases, movement, Harvest, and building.
- `cards.odin`: public immutable `SWARM_CARDS`, `CORP_CARDS`, `AI_CARDS`, and `NOMAD_CARDS` catalog arrays, `LookupCard`, and payment/kind validation. Card IDs are zero-based within each faction; `LookupCard` returns the name, kind, Data cost, and printed text.
- `effects.odin`, `observations.odin`, and `protocol_*.odin`: Protocol choices, card effects, and staged observations for informational cards.
- `combat.odin`: Strike resolution, Combat cards, and `CombatChoice` / `CombatResult`.
- `factions.odin`: Proliferate, Reinvest, Rewire, relay destruction, and Hit and Run.
- `scoring.odin`: objective and directive checks, faction VP, final scores, and tiebreaks.
- `*_test.odin`: Odin `@(test)` coverage. Test files are excluded from the JavaScript target because Odin's `core:testing` is not supported there.

## Setup and randomness

Fill a `SetupConfig` and call `SetupGame(&game, config)`. Invalid input returns `false` and leaves the output unchanged. The caller selects factions and starts. For reproducible random setup, call `PrepareShuffledSetup(&config, seed)` to select the first player and shuffle the faction decks, terrain, and directives; alternatively, supply those orders and first player explicitly.

- Set `playerCount` to 2–4 and `firstPlayer` to a valid player index. The first `playerCount` entries of `players` must have distinct factions and distinct starts from `START_HEXES`: `{-2, 0}`, `{0, -2}`, `{2, 0}`, `{0, 2}`. Two players must use opposite starts.
- For each player, the first `FactionDeckSize(faction)` entries of `deck` must be a permutation of that faction's card IDs: Swarm 12, Corp 14, AI 13, Nomad 12. Remaining entries are ignored. Decks are bottom-to-top: draws take the last remaining entry, including the initial three cards.
- `terrainOrder` must be a permutation of `0..<15`, indexing `TERRAIN_POOL`: four Energy Nodes, four Data Nodes, four Cover, and three Open. Terrain is dealt in board-array order, iterating `q` then `r` from -2 to 2, skipping invalid coordinates, rifts, and all four marked starts. Unused entries are ignored after validation; starts remain Open.
- `directiveOrder` must be a permutation of `0..<12`. Directive IDs follow the zero-based table order in `DESIGN.md`. Entries are dealt from the beginning in clockwise player order starting with `firstPlayer`: two per player, or three for Nomad.
- `SelectRifts` derives 0, 3, or 6 Rift positions from the selected starts. In 2P both unused potential starts become Rifts; the remaining Rifts are outer non-start hexes ranked by distance to the nearest selected start, with ties broken by ascending axial `q` then `r`. In 3P the unused fourth start stays active and Open.
- `PrepareShuffledSetup` saves its resulting RNG state in `randomSeed`; when supplying orders yourself, set `randomSeed` explicitly. The AI Protocol **Override** uses the game-owned RNG to select an opposing hand index. `RandomIndex` uses xorshift and rejection sampling; a zero state is replaced by `0x9e3779b97f4a7c15` when randomness is next requested.

The same valid configuration, seed, and action/choice sequence produce the same state and random results. Preserve `randomState` with the rest of a game snapshot to reproduce later results. This PRNG is predictable, not cryptographic; the caller is responsible for any entropy and secrecy requirements. The optional `PrepareShuffledSetup` procedure produces setup orders from the supplied seed. A failed atomic Protocol or combat action does not advance the original game's RNG state. See `TestSetupAndTurns` in `turns_test.odin` for a concrete setup.

## Calling the engine

1. Call `SetupGame`. A successful game starts in `.Await_Turn`, round 1, with the configured first player.
2. Call `BeginTurn(&game)`. It expires that player's Fortify and Relay Shield effects, grants baseline 1 Energy and 1 Data plus one resource per controlled matching node, draws one card if possible, sets 3 AP, and enters `.Acting`. The hand limit is 5. An empty deck or full hand prevents drawing; discards are not reshuffled.
3. Call legal actions for `game.currentPlayer`: `MoveUnits`, `Harvest`, `BuildUnit`, `BuildStructure`, `PlayProtocol`, `BeginInformationalProtocol`, `StrikeWithCards`, or the applicable `Proliferate`, `Reinvest`, `RewireRelay`, `RewireTerrain`, `HitAndRunWithCards`, or `DestroyRelay`. `MoveUnitsVia` is available during Warpath. Actions validate their own preconditions and costs; a player may end early. `DestroyRelay` is a free, once-per-turn enemy-unit action rather than an AP action.
4. Call `EndTurn(&game)`. Unspent AP and end-of-turn effects are cleared. The next player enters `.Await_Turn`; after all players have taken a turn, the game enters `.Score_Objective`.
5. Call `ScoreAndCompleteObjective(&game)` once in `.Score_Objective`. It awards each qualifying player 2 public VP, increments their objectives-scored counter, and advances the phase. For rounds 1–5, first player rotates clockwise and round combat-win counters reset; after round 6, the phase becomes `.Finished`.
6. In `.Finished`, call `CalculateFinalScores(&game, &scores)`. It calculates results without changing the game and can be called repeatedly. `scores.players` contains per-player breakdowns; `scores.winners` and `winnerCount` identify all winners, including shared victories. Invalid input leaves the output unchanged.

## Playing Protocol cards

```odin
ProtocolChoice :: struct {
    from, to: Hex,
    other: int,
    resource: ResourceKind, // .Energy or .Data
    terrain: Terrain,       // .Open, .Cover, .Energy_Node, .Data_Node
    target: TokenKind,      // .Structure or .Relay
    cardIndex: int,
    option: bool,
}

PlayProtocol :: proc(game: ^Game, handIndex: int, choice: ProtocolChoice) -> bool
```

`handIndex` is the current player's **hand index**, not the faction card ID. The game must be in `.Acting`; the card must be a Protocol, with space in the discard pile and sufficient AP and Data. For non-informational cards, `PlayProtocol` resolves on a copy: it pays 1 AP and the card's Data cost, discards the card, increments `cardsPlayed`, and applies the effect. On any invalid choice or other failure it returns `false` and leaves the entire original game unchanged, including resources, hands, board, counters, and RNG state. On success it returns `true`, even when an effect such as a capped gain or an unavailable draw has no further result.

For example, given a legal Swarm Replicate card at `handIndex`, a controlled hex at the center with room, and enough AP and Data:

```odin
ok := PlayProtocol(&game, handIndex, ProtocolChoice{to = Hex{0, 0}})
```

`ValidateCard` checks card kind, hand/discard space, and payment, **not** the effect or target. Public `DiscardAndPayCard` and the `Apply*Protocol` helpers do not execute complete actions. Use `PlayProtocol` for non-informational cards and the staged API below for cards that reveal information. The card is discarded before the effect is applied, so draws see the freed hand slot. Gains are capped at 8 and draws stop at the hand limit or empty deck; a failed draw does not by itself reject a card unless stated below.

### Informational Protocols

`BeginInformationalProtocol(&game, handIndex, other)` handles Swarm Sense, Audit, Data Spike, and Ping. It validates and commits the AP/Data cost and discard **before** returning a `ProtocolObservation` containing the revealed hand or top deck cards. Use `other` for Audit and Data Spike; it is ignored for the deck cards. Data Spike completes immediately. The other three enter `.Protocol_Choice`: call `FinishInformationalProtocol(&game, choice)` after seeing the observation. Use `cardIndex` to pick the card for Swarm Sense or Audit, and `option` for Ping. The Audit target is fixed at the beginning. While a choice is pending, normal actions and `EndTurn` are rejected; an invalid finish leaves the paid action pending so it can be retried. `PlayProtocol` rejects these four cards to prevent a reveal without the staged flow.

The tables list the fields each card actually reads; unused fields are ignored. Single-hex choices use `to`, except where noted. `other` is an opponent's player index. `target` selects a token kind, not its owner. Zero-initialized fields are not generic “no choice” values: for example `other = 0`, `cardIndex = 0`, `.Energy`, `.Open`, and `.Structure` can all be meaningful choices. Hand indices can change after any discard or draw.

### Swarm Protocols

| ID | Card (Data) | Fields | Implemented choice/effect |
|---|---|---|---|
| 4 | Sacrifice (0) | `to` | Remove one own unit on an active hex, even if contested; draw up to two cards. An unboosted unit is removed first. |
| 5 | Swarm Sense (0) | `cardIndex` | `0` draws the top card; `1` draws the second card. The other of the top two goes to the bottom. With one card only `0` is valid; an empty deck rejects the play. |
| 6 | Burrow (1) | `from`, `to` | Move one unit to an adjacent active hex with room and no enemy units or structures. The unit may leave a contested hex. |
| 7 | Replicate (1) | `to` | Place one unit on a controlled hex with room. |
| 8 | Hive Mind (1) | `to` | Give the own units currently on an active hex +1 strength until end of turn; the hex may be contested. |
| 9 | Corrode (2) | `to`, `target` | Attempt to destroy an enemy structure or destroy an enemy relay on a hex adjacent to an own unit. A structure target must have exactly one enemy structure owner. A structure shield absorbs the attempt; relay shields do not stop card effects. |
| 10 | Brood (2) | `from`, `to` | Place one unit on each of two distinct controlled hexes with room; they need not be adjacent. `from` is a placement, not a movement source. |
| 11 | Endless (0) | — | Gain 2 Energy. |

### Corp Protocols

| ID | Card (Data) | Fields | Implemented choice/effect |
|---|---|---|---|
| 3 | Hostile Takeover (2) | `other`, `resource` | Transfer one chosen resource from an opponent. The opponent must have it and the Corp must have room for it. |
| 4 | Fortify (1) | `to` | A controlled own structure gains +2 defense until the start of its owner's next turn. |
| 5 | Dividend (0) | — | Gain 1 Data per controlled own structure, up to 3. |
| 6 | Lobby (1) | — | Draw up to two cards. |
| 7 | Redundancy (2) | `to` | Shield a controlled own structure that is not already shielded. |
| 8 | Bailout (0) | — | Gain 2 Data. |
| 9 | Contract (1) | `to` | Gain 3 of the resource produced by a controlled Energy or Data node. |
| 10 | Automate (1) | — | The next successful Build Unit or Build Structure this turn costs no resources, but still costs 1 AP. |
| 11 | Audit (1) | `other`, `cardIndex` | Discard the selected index from an opponent's current hand. The hand must contain that card and the opponent's discard pile must have space. |
| 12 | Shareholder Value (1) | — | Draw one card and gain 1 Data. |
| 13 | Monopoly (2) | `resource` | Each opponent with that resource loses one, and the Corp gains each transferred resource up to the cap. Opponents still lose theirs if the Corp is already capped. |

### AI Protocols

| ID | Card (Data) | Fields | Implemented choice/effect |
|---|---|---|---|
| 3 | Data Spike (1) | `other` | `BeginInformationalProtocol` returns the chosen opponent's hand and completes the play. An empty hand is allowed. |
| 4 | Reroute (1) | `from`, `to` | Move an owned relay to an adjacent controlled active hex without a relay. The destination must be controlled before the relay moves. |
| 5 | Cascade (0) | — | Draw one card per owned active relay, up to two. |
| 6 | Override (2) | `other` | Discard a random card from the opponent's nonempty hand, using `game.randomState`; their discard pile needs room. `cardIndex` is ignored. |
| 7 | Ping (0) | `option` | If `true`, put the top deck card on the bottom before drawing; if `false`, draw the top card. An empty deck is allowed; with one card the reorder has no effect. |
| 8 | Mesh (1) | `to` | Place an owned relay on a controlled hex without a relay. |
| 9 | Relay Shield (1) | — | Protect owned relays from the enemy-unit `DestroyRelay` action until the start of the owner's next turn, not from card effects. |
| 10 | Fork (1) | `to`, `resource` | Choose a controlled hex and gain the selected resource per adjacent owned active relay, up to 2. |
| 11 | Compile (2) | `to`, `terrain` | Change a controlled hex to a *different* terrain type; gain 1 of the corresponding resource if the new type is a node. |
| 12 | Pulse (0) | — | Each adjacent owned AI relay contributes an additional +1 defense until end of turn. |

### Nomad Protocols

| ID | Card (Data) | Fields | Implemented choice/effect |
|---|---|---|---|
| 5 | Scorched Earth (1) | `to`, `target` | Require control of the target hex; destroy an own structure or any relay there, then gain 3 Energy. This allows Nomad to destroy an AI relay in a hex it controls. A structure shield is consumed and the Energy is still gained. |
| 6 | Smoke and Mirrors (0) | — | Draw one card. |
| 7 | Forage (1) | — | Gain 1 Energy and 1 Data. |
| 8 | Strike Team (1) | `from`, `to`, `option`, `target` | Move one unit to an adjacent hex with room and no enemy units. `option = false` leaves any enemy structure or relay intact. With `option = true`, select an enemy `.Structure` or `.Relay` to destroy; the selected relay may coexist with a structure. A shielded structure consumes its shield while the unit still moves; the structure remains in the occupied hex. |
| 9 | Flee (0) | `from`, `to` | Move one unit from a hex containing enemy units to an adjacent hex with room and no enemy units or structures. |
| 10 | Tribute (2) | `other`, `resource` | The caller supplies the opponent's resource choice. Transfer one available resource from that opponent and gain one additional resource of the same type, subject to the cap; the transfer requires room. |
| 11 | Warpath (2) | — | Enable a free first Strike if no Strike has yet occurred this turn, and enable `MoveUnitsVia` for the rest of the turn. |

## Strike and Hit and Run with Combat cards

```odin
NO_CARD :: -1

CombatMove :: struct {
    from, to: Hex,
}
CombatChoice :: struct {
    attackerCard, defenderCard: int,
    plunder: ResourceKind,
    attackerMoves, defenderMoves: [UNIT_CAP]CombatMove,
    attackerMoveCount, defenderMoveCount: int,
}

StrikeWithCards :: proc(game: ^Game, from, to: Hex, count: int, capture: bool, choice: CombatChoice) -> (CombatResult, bool)
HitAndRunWithCards :: proc(game: ^Game, from, to: Hex, count: int, doStrike, capture: bool, choice: CombatChoice) -> (CombatResult, bool)
```

Both card fields are **indices into the respective player's current hand**, not card IDs. Use `NO_CARD` for each side declining a card; a zero-initialized `CombatChoice{}` selects hand index 0 for **both** sides, not no cards. Combat always uses these card-aware entry points; use `CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD}` to decline card reveals.

```odin
choice := CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD}
result, ok := StrikeWithCards(&game, from, to, count, true, choice)
```

The returned `bool` reports whether the action was legal, **not** victory. Inspect `CombatResult.attackerWon`, `attackerStrength`, `defenderStrength`, `unitDestroyed`, `structureDestroyed`, and `captured` for the outcome. Both card-aware actions resolve on a copy: an invalid card, cost, capture, Plunder choice, or post-combat move rejects the entire action without spending AP or cards or changing the original game.

### Resolution and choices

- A Strike costs 1 AP unless Warpath makes the first Strike of the turn free. It commits `count` own units from one active hex to an adjacent active target. The target must contain units or a structure belonging to exactly one opponent; a relay alone is not a target. A structure without defending units is a valid target. Strike does not require the defender to control the target.
- Each side may select at most one Combat card, but at most **one card total** is revealed. If both select a card, the attacker's selection takes priority unless the defender selected **Counter-Intelligence**, which suppresses the attacker's card. The suppressed selection must identify a Combat card but is not paid for, discarded, or applied. The revealed card costs its Data, is discarded, and increments its player's `cardsPlayed`; it costs no additional AP. Counter-Intelligence cannot be played by the attacker.
- Attacking strength is committed units plus their boosts and card bonus. Defending strength is defending units plus their boosts, Cover (+1), an own structure (+1, plus Fortify's +2), adjacent owned AI relays (+1 each, plus Pulse's +1 each), and card bonus. Ties favor the defender. Boosted units participate first; casualties remove unboosted participants first.
- The winner gains a combat win and the loser loses one participating unit if available. If the attacker wins and no defending units remain, `capture = true` moves one attacker into the target on a normal Strike and attempts to destroy the defending structure. For Hit and Run the attackers have already moved there. A structure shield can absorb that attempt, so `captured` can be true while `structureDestroyed` is false and the hex remains contested. If an attempted capture requires an illegal move, the entire action is rejected; the capture flag has no effect when the attacker loses or defenders remain.
- For triggered post-combat moves, set the appropriate move count and the first entries of that side's `CombatMove` array. Moves are optional, applied in array order after casualties and capture, defender first. Each moves one surviving **participant** one hex to an active destination with room and no enemy units or structures. A moved participant cannot move again through these choices; uncommitted friendly units cannot be moved. Nonzero move counts require a card and outcome that permit them; an illegal move or count rolls back the action. Except for the side whose card was suppressed, counts must be zero when no movement effect applies.
- `plunder` is read only when an attacking Nomad wins with Plunder. Choose `.Energy` or `.Data`: if either resource can be transferred, the chosen one must be available from the defender and fit under the attacker's cap. If neither can be transferred, a valid resource choice has no effect. The check happens after card costs.

### Combat card behavior

Card IDs below are faction-local catalog IDs; pass the **hand index** in `CombatChoice`. Cards with defense-only bonuses can still be selected on attack, but that bonus will not apply. Movement and other conditional effects also require the stated side and outcome.

| Faction | ID | Card | Implemented effect / extra choice |
|---|---|---|---|
| Swarm | 0 | Overwhelm | +1 per own unit in the relevant combat hex beyond the first, max +2. |
| Swarm | 1 | Chitin | +2 when defending. |
| Swarm | 2 | Rush | +2 when attacking with more participants than the defending unit count. |
| Swarm | 3 | Frenzy | On an attacker win, up to `UNIT_CAP` surviving attackers may each make one `attackerMoves` move. |
| Corp | 0 | Ablative Plating | +2 when defending, or +3 if the target has the defender's structure. |
| Corp | 1 | Security Detail | +1 per adjacent controlled own structure, max +2, on either side. |
| Corp | 2 | Counter-Intelligence | Defender only; suppresses the attacker's card as described above. |
| AI | 0 | Firewall | +2 when defending, or +3 if an owned relay is adjacent to the target. |
| AI | 1 | Feedback Loop | +1 per adjacent active relay of any owner, max +2, on either side. |
| AI | 2 | Ghost Protocol | +1 when defending; on a loss on either side, optionally move one surviving participant using that side's moves. |
| Nomad | 0 | Boarding Party | +1 per own unit in the combat source hex, including uncommitted units, on either side. For Hit and Run the source used here is the destination after movement. |
| Nomad | 1 | Evasive Maneuvers | +2 when defending. |
| Nomad | 2 | Ambush | +2 on either side if the defender has a structure or their relay in the target hex. |
| Nomad | 3 | Smoke Screen | After a win or loss, optionally move one surviving participant using that side's moves. |
| Nomad | 4 | Plunder | On an attacker win, transfer one defender resource using `plunder`, subject to availability and caps above. It has no transfer effect for a defending Nomad. |

### Hit and Run

`HitAndRunWithCards` is Nomad-only, costs 1 AP, and first moves 1–2 units to an adjacent active hex, including an enemy-controlled hex. Total destination capacity is checked **before** combat. If the destination contains enemy units or a structure, there must be exactly one opposing player with those pieces and that player must control the destination before the move. Set `doStrike` to choose whether to make the free Strike; only moved units participate as attackers. The free Strike counts for Warpath, and structure-only defenders are allowed. Units can remain together in the destination if combat is declined or does not clear it.

If there are no enemy units or structures at the destination, `doStrike` must be false. Whenever a Strike is declined, both card fields must be `NO_CARD` and both move counts must be zero. No combat occurs and the returned `CombatResult` is zero-valued; do not interpret its `attackerWon` as a combat loss. A relay alone is not a Strike target. As with normal Strike, the boolean return indicates action legality.

## Temporary effects and destruction

- **Hive Mind:** `boostedUnits` tracks the units affected at play time. Boosts move with units, contribute +1 each to combat, and clear at their owner's `EndTurn`. New units are not automatically boosted, and replaying the effect sets the current hex's boosted count rather than stacking another +1.
- **Automate, Pulse, Warpath:** clear at the owner's `EndTurn`. Automate is consumed only by a successful Build Unit or Build Structure; the AP cost remains. Warpath does not reset `struckThisTurn` when played, and a Hit and Run Strike also sets that flag. `MoveUnitsVia` moves 1–2 units across exactly two adjacent steps for 1 AP; the source, intermediate, and destination must be active hexes, the destination must differ from the source, the intermediate hex must contain an enemy unit, and the destination must have room and no enemy units or structures.
- **Fortify and Relay Shield:** last until the owner's next `BeginTurn`, when they are cleared before income. Fortify is also cleared if its structure is destroyed. Relay Shield blocks `DestroyRelay` by enemy units, but not Corrode or Strike Team.
- **Redundancy:** a structure shield persists across turns until a destruction attempt consumes it. That attempt does not destroy the structure or credit a destruction. Corrode and Scorched Earth still succeed when a shield absorbs their attempt; capture may also succeed. Strike Team still completes its move when Redundancy absorbs the destruction attempt; the structure remains in the occupied hex.
- Enemy structures and relays destroyed by effects are counted for the actor where the shared destruction helpers apply. Self-destruction is not credited as enemy destruction. Transfers increment the recipient's `resourcesStolen`; resources an opponent loses to a capped Monopoly are not transferred or credited.

## Hidden information and caller responsibilities

`Game` contains all players' hands, deck orders, directives, and RNG state in plain state; the engine does not enforce visibility or produce player-specific views. Do not expose the full state or predictable RNG state to an untrusted player. The caller must decide which player may inspect which information, collect private choices, and control when information is revealed.

`BeginInformationalProtocol` returns only the cards revealed by the paid card effect. For Audit, Swarm Sense, and Ping the engine then waits for `FinishInformationalProtocol`; Tribute's resource is chosen by the targeted opponent and supplied to `PlayProtocol`. Combat receives both players' card selections and any conditional post-combat choices in one call. The caller must route each observation to its intended player; `Game` itself remains complete, unfiltered state.

## Scoring

The six public objective checks are fixed by round: control 2 hexes; hold 5 combined resources; control 2 developed hexes; win a combat that round; have 4 units; and control 4 hexes (3 in 2P). `ObjectiveMet` and `CalculateScoringStats` can be used for inspection. A developed hex is a controlled active hex containing a resource node, any structure, or any relay; ownership of the token is not required.

Final scoring adds public VP, faction VP, and 2 VP per completed secret directive. `DirectiveMet` and `FactionVp` expose individual checks. The faction formulas include 2P adjustments; AI network bonuses use the largest connected group of owned relays. Ties are broken by public VP, completed directives, faction VP, then remaining Energy plus Data; an exact tie is shared.

## Rule clarifications

`DESIGN.md` v1.1 records the exact axial start coordinates, deterministic Rift selection and tie-breaking, the one-card-per-Strike limit, and Hit and Run's movement exception. The printed individual card costs are authoritative; the deck summaries in the design are calculated from those costs.

Scorched Earth requires a controlled hex; Nomad may destroy an AI relay in a hex it controls. Starting hexes remain Open and cannot be changed by Rewire or Compile. Structure and relay destruction, including shields and scoring counters, use shared rules helpers.

The package contains pure game-state logic only. It does not implement UI, networking, persistence, or rendering. The caller supplies player choices and handles any access restrictions on complete game state and returned observations.

## Check and test

Install Odin and, on Windows, the Windows SDK and linker needed to build test executables. From the repository root, in PowerShell, initialize the local build environment before running the checks and tests:

```powershell
. C:\BuildTools\devcmd.ps1
odin check logicEngine -no-entry-point -vet
odin check logicEngine -no-entry-point -target:js_wasm32
odin test logicEngine
```

For example, to run the tests from another shell in a single PowerShell process:

```powershell
powershell -NoProfile -Command ". C:\BuildTools\devcmd.ps1; odin test logicEngine"
```

The first two commands type-check the package for desktop and JavaScript/WebAssembly without requiring `main`; the third builds and runs its `@(test)` procedures. These tests cover implemented behavior, not complete conformance to every rule in the design.
