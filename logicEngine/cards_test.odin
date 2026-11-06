#+build !js

package logicEngine

import "core:testing"

@(test)
TestCardCatalog :: proc(t: ^testing.T) {
	factions := [?]Faction{.Swarm, .Corp, .AI, .Nomad}
	sizes := [?]int{12, 14, 13, 12}
	combatCounts := [?]int{4, 3, 3, 5}
	for faction, f in factions {
		combatCount := 0
		for id in 0..<sizes[f] {
			card, ok := LookupCard(faction, id)
			testing.expect(t, ok && len(card.name) > 0 && len(card.text) > 0)
			testing.expect(t, card.dataCost >= 0 && card.dataCost <= 2)
			if card.kind == .Combat {
							combatCount += 1
						} else {
							testing.expect(t, card.kind == .Protocol)
						}
		}
		testing.expect_value(t, combatCount, combatCounts[f])
		_, negative := LookupCard(faction, -1)
		_, pastEnd := LookupCard(faction, sizes[f])
		testing.expect(t, !negative && !pastEnd)
	}
	_, invalid := LookupCard(Faction(99), 0)
	testing.expect(t, !invalid)
	card, _ := LookupCard(.Swarm, 11)
	testing.expect_value(t, card.name, "Endless")
	card, _ = LookupCard(.Corp, 13)
	testing.expect_value(t, card.name, "Monopoly")
	card, _ = LookupCard(.AI, 12)
	testing.expect_value(t, card.name, "Pulse")
	card, _ = LookupCard(.Nomad, 11)
	testing.expect_value(t, card.name, "Warpath")
}

@(test)
TestCardPayment :: proc(t: ^testing.T) {
	player := Player{faction = .Swarm, ap = 1, resources = {0, 2}, hand = {0, 9, 1, 0, 0}, handCount = 3}
	before := player
	testing.expect(t, !ValidateCard(nil, 0, .Combat))
	testing.expect(t, !DiscardAndPayCard(&player, 1, .Combat))
	testing.expect(t, !DiscardAndPayCard(&player, -1, .Protocol))
	testing.expect(t, !DiscardAndPayCard(&player, 3, .Protocol))
	testing.expect(t, !DiscardAndPayCard(&player, 1, CardKind(99)))
	testing.expect_value(t, player, before)
	testing.expect(t, DiscardAndPayCard(&player, 1, .Protocol))
	testing.expect_value(t, player.ap, 0)
	testing.expect_value(t, player.resources.data, 0)
	testing.expect_value(t, player.handCount, 2)
	testing.expect_value(t, player.hand[1], 1)
	testing.expect_value(t, player.discard[0], 9)
	testing.expect_value(t, player.cardsPlayed, 1)
	testing.expect(t, DiscardAndPayCard(&player, 0, .Combat))
	testing.expect_value(t, player.ap, 0)
	testing.expect_value(t, player.discard[1], 0)
	before = player
	testing.expect(t, !DiscardAndPayCard(&player, 0, .Protocol))
	testing.expect_value(t, player, before)
	player.discardCount = len(player.discard)
	testing.expect(t, !ValidateCard(&player, 0, .Combat))
	player.discardCount = 0
	player.hand[0] = 9
	player.ap = 1
	testing.expect(t, !ValidateCard(&player, 0, .Protocol)) // Not enough Data.
	player.resources.data = 2
	player.ap = 0
	testing.expect(t, !ValidateCard(&player, 0, .Protocol))
	player.ap = 1
	player.hand[0] = 12
	testing.expect(t, !ValidateCard(&player, 0, .Protocol))
	player.handCount = len(player.hand) + 1
	testing.expect(t, !ValidateCard(&player, 0, .Protocol))
	player.handCount = 1
	player.hand[0] = 0
	player.resources.energy = -1
	testing.expect(t, !ValidateCard(&player, 0, .Combat))
	player.resources.energy = 0
	player.ap = -1
	testing.expect(t, !ValidateCard(&player, 0, .Combat))
}
