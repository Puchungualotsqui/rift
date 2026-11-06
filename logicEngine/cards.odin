package logicEngine

CardKind :: enum {
	Combat,
	Protocol,
}

CardDefinition :: struct {
	name: string,
	kind: CardKind,
	dataCost: int,
	text: string,
}

// IDs are zero-based within each faction, in DESIGN.md table order.
SWARM_CARDS :: [?]CardDefinition{
	{"Overwhelm", .Combat, 0, "+1 strength per unit in the hex beyond the first (max +2)."},
	{"Chitin", .Combat, 0, "+2 defense this combat."},
	{"Rush", .Combat, 1, "+2 strength if you have more units in the combat than the defender."},
	{"Frenzy", .Combat, 1, "If you win this combat, each surviving attacker may move 1 hex."},
	{"Sacrifice", .Protocol, 0, "Destroy 1 of your units. Draw 2 cards."},
	{"Swarm Sense", .Protocol, 0, "Look at top 2 cards of your deck. Draw 1, put the other on the bottom."},
	{"Burrow", .Protocol, 1, "Move 1 unit to an adjacent hex, ignoring enemy units (must end in a hex without enemy units)."},
	{"Replicate", .Protocol, 1, "Place 1 unit on a hex you control."},
	{"Hive Mind", .Protocol, 1, "All your units in one hex gain +1 strength until end of turn."},
	{"Corrode", .Protocol, 2, "Destroy 1 enemy structure or relay in a hex adjacent to one of your units."},
	{"Brood", .Protocol, 2, "Place 2 units, each on a different controlled hex."},
	{"Endless", .Protocol, 0, "Gain 2 Energy."},
}

CORP_CARDS :: [?]CardDefinition{
	{"Ablative Plating", .Combat, 1, "+2 defense. +3 instead if the defending hex contains your structure."},
	{"Security Detail", .Combat, 1, "+1 strength for each structure you control adjacent to the combat hex (max +2)."},
	{"Counter-Intelligence", .Combat, 0, "The attacker cannot reveal a combat card this combat."},
	{"Hostile Takeover", .Protocol, 2, "Steal 1 resource (Energy or Data) from an opponent."},
	{"Fortify", .Protocol, 1, "A structure you control gains +2 defense until the start of your next turn."},
	{"Dividend", .Protocol, 0, "Gain 1 Data for each structure you control (max 3)."},
	{"Lobby", .Protocol, 1, "Draw 2 cards."},
	{"Redundancy", .Protocol, 2, "Place a shield token on a structure you control. The next time that structure would be destroyed, remove the shield instead. Max 1 shield per structure."},
	{"Bailout", .Protocol, 0, "Gain 2 Data."},
	{"Contract", .Protocol, 1, "Choose a resource node you control. Gain 3 of that node's resource."},
	{"Automate", .Protocol, 1, "Your next Build Unit or Build Structure action this turn costs 0 resources."},
	{"Audit", .Protocol, 1, "Look at an opponent's hand. That player discards 1 card of your choice."},
	{"Shareholder Value", .Protocol, 1, "Draw 1 card and gain 1 Data."},
	{"Monopoly", .Protocol, 2, "Choose a resource type. Each opponent loses 1 of that resource. You gain 1 of that type per opponent affected."},
}

AI_CARDS :: [?]CardDefinition{
	{"Firewall", .Combat, 1, "+2 defense. +3 instead if a relay you control is adjacent to the defending hex."},
	{"Feedback Loop", .Combat, 1, "+1 strength for each relay adjacent to the combat hex (max +2)."},
	{"Ghost Protocol", .Combat, 0, "+1 defense. If you lose this combat, move 1 surviving unit to an adjacent hex."},
	{"Data Spike", .Protocol, 1, "Look at an opponent's hand."},
	{"Reroute", .Protocol, 1, "Move 1 relay you control to an adjacent hex you control."},
	{"Cascade", .Protocol, 0, "Draw 1 card for each relay you control (max 2)."},
	{"Override", .Protocol, 2, "Target opponent discards 1 card at random."},
	{"Ping", .Protocol, 0, "Look at the top card of your deck. You may put it on the bottom. Draw 1 card."},
	{"Mesh", .Protocol, 1, "Place 1 relay on a hex you control that doesn't have a relay."},
	{"Relay Shield", .Protocol, 1, "Until your next turn, your relays cannot be destroyed by enemy units. (Card effects still work.)"},
	{"Fork", .Protocol, 1, "Choose a hex you control. Gain 1 Energy or 1 Data for each relay adjacent to that hex (max 2)."},
	{"Compile", .Protocol, 2, "Change the terrain of a hex you control to any terrain type. If you change it to a node type, gain 1 of that resource."},
	{"Pulse", .Protocol, 0, "Your relays give +1 defense until end of turn."},
}

NOMAD_CARDS :: [?]CardDefinition{
	{"Boarding Party", .Combat, 1, "+1 strength for each unit you have in the attacking hex."},
	{"Evasive Maneuvers", .Combat, 0, "+2 defense this combat."},
	{"Ambush", .Combat, 1, "+2 strength if the defender has a structure or relay in the hex."},
	{"Smoke Screen", .Combat, 1, "After combat (win or lose), move 1 surviving unit to an adjacent hex."},
	{"Plunder", .Combat, 1, "If you win this combat, gain 1 Energy or 1 Data from the defender."},
	{"Scorched Earth", .Protocol, 1, "Destroy 1 structure or relay you control. Gain 3 Energy."},
	{"Smoke and Mirrors", .Protocol, 0, "Draw 1 card."},
	{"Forage", .Protocol, 1, "Gain 1 Energy and 1 Data."},
	{"Strike Team", .Protocol, 1, "Move 1 unit to an adjacent hex. If that hex contains an enemy structure or relay, you may destroy it (no combat needed)."},
	{"Flee", .Protocol, 0, "Move 1 unit from a hex containing enemy units to an adjacent hex (disengage without combat)."},
	{"Tribute", .Protocol, 2, "Choose an opponent. They give you 1 resource of their choice. You gain 1 additional resource of the same type."},
	{"Warpath", .Protocol, 2, "This turn, your first Strike costs 0 AP. Your units may move through hexes containing enemy units this turn (they still cannot end there)."},
}

// Returns a copy; invalid factions and IDs return false.
LookupCard :: proc(faction: Faction, id: int) -> (CardDefinition, bool) {
	cards: []CardDefinition
	switch faction {
	case .Swarm:
		cardDefinitions := SWARM_CARDS
		cards = cardDefinitions[:]
	case .Corp:
		cardDefinitions := CORP_CARDS
		cards = cardDefinitions[:]
	case .AI:
		cardDefinitions := AI_CARDS
		cards = cardDefinitions[:]
	case .Nomad:
		cardDefinitions := NOMAD_CARDS
		cards = cardDefinitions[:]
	case:
		return {}, false
	}
	if id < 0 || id >= len(cards) do return {}, false
	return cards[id], true
}

// Checks only card kind, hand/discard space and payment, not effect legality.
// Combat reveal costs no AP here; the Strike's AP is paid separately.
ValidateCard :: proc(player: ^Player, handIndex: int, kind: CardKind) -> bool {
	if player == nil || (kind != .Combat && kind != .Protocol) do return false
	if player.handCount < 0 || player.handCount > len(player.hand) ||
		handIndex < 0 || handIndex >= player.handCount ||
		player.discardCount < 0 || player.discardCount >= len(player.discard) {
				return false
			}
	card, ok := LookupCard(player.faction, player.hand[handIndex])
	if !ok || card.kind != kind || player.ap < 0 || player.resources.energy < 0 ||
		player.resources.data < card.dataCost {
				return false
			}
	if kind == .Protocol && player.ap < 1 do return false
	return true
}

// Only use after validating the complete effect; no card effects exist yet.
DiscardAndPayCard :: proc(player: ^Player, handIndex: int, kind: CardKind) -> bool {
	if !ValidateCard(player, handIndex, kind) do return false
	card, _ := LookupCard(player.faction, player.hand[handIndex])
	ap := 0
	if kind == .Protocol do ap = 1
	if !PayCost(player, ap, Resources{0, card.dataCost}) do return false
	player.discard[player.discardCount] = player.hand[handIndex]
	player.discardCount += 1
	for i in handIndex..<player.handCount - 1 {
		player.hand[i] = player.hand[i + 1]
	}
	player.handCount -= 1
	player.hand[player.handCount] = 0
	player.cardsPlayed += 1
	return true
}
