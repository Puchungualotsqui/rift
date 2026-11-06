#+build !js

package logicEngine

import "core:testing"

@(test)
TestDataSpikeRevealsAfterPayment :: proc(t: ^testing.T) {
	game := IntegrationProtocolGame(.AI, 3)
	before := game
	_, ok := BeginInformationalProtocol(&game, 1, 0)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	testing.expect(t, !PlayProtocol(&game, 1, {other = 1}))
	testing.expect_value(t, game, before)

	observation, revealed := BeginInformationalProtocol(&game, 1, 1)
	testing.expect(t, revealed)
	testing.expect_value(t, observation.kind, ObservationKind.Hand)
	testing.expect_value(t, observation.owner, 1)
	testing.expect_value(t, observation.count, 3)
	testing.expect_value(t, observation.cardIds, game.players[1].hand)
	testing.expect_value(t, game.players[0].ap, 2)
	testing.expect_value(t, game.players[0].resources.data, 5)
	testing.expect_value(t, game.players[0].cardsPlayed, 2)
	testing.expect_value(t, game.phase, Phase.Acting)
}

@(test)
TestAuditKeepsPaidChoicePending :: proc(t: ^testing.T) {
	game := IntegrationProtocolGame(.Corp, 11)
	observation, ok := BeginInformationalProtocol(&game, 1, 1)
	testing.expect(t, ok)
	testing.expect_value(t, observation.kind, ObservationKind.Hand)
	testing.expect_value(t, observation.owner, 1)
	testing.expect_value(t, observation.count, 3)
	testing.expect_value(t, observation.cardIds[1], 1)
	testing.expect_value(t, game.phase, Phase.Protocol_Choice)
	testing.expect_value(t, game.players[0].ap, 2)
	testing.expect_value(t, game.players[0].resources.data, 5)
	pending := game
	testing.expect(t, !EndTurn(&game))
	testing.expect(t, !MoveUnits(&game, {0, 0}, {0, 1}, 1))
	testing.expect(t, !FinishInformationalProtocol(&game, {cardIndex = 99}))
	testing.expect_value(t, game, pending)
	testing.expect(t, FinishInformationalProtocol(&game, {other = 0, cardIndex = 1}))
	testing.expect_value(t, game.phase, Phase.Acting)
	testing.expect_value(t, game.players[1].handCount, 2)
	testing.expect_value(t, game.players[1].discard[0], 1)
	testing.expect(t, !FinishInformationalProtocol(&game, {}))
}

@(test)
TestSwarmSenseAndPingRevealDeckBeforeChoice :: proc(t: ^testing.T) {
	game := IntegrationProtocolGame(.Swarm, 5)
	player := &game.players[0]
	top, second := player.deck[player.deckCount - 1], player.deck[player.deckCount - 2]
	observation, ok := BeginInformationalProtocol(&game, 1, NO_PLAYER)
	testing.expect(t, ok)
	testing.expect_value(t, observation.kind, ObservationKind.Deck)
	testing.expect_value(t, observation.owner, 0)
	testing.expect_value(t, observation.count, 2)
	testing.expect_value(t, observation.cardIds[0], top)
	testing.expect_value(t, observation.cardIds[1], second)
	pending := game
	testing.expect(t, !FinishInformationalProtocol(&game, {cardIndex = 2}))
	testing.expect_value(t, game, pending)
	testing.expect(t, FinishInformationalProtocol(&game, {cardIndex = 1}))
	testing.expect_value(t, game.players[0].hand[2], second)
	testing.expect_value(t, game.players[0].deck[0], top)

	game = IntegrationProtocolGame(.AI, 7)
	player = &game.players[0]
	top, second = player.deck[player.deckCount - 1], player.deck[player.deckCount - 2]
	observation, ok = BeginInformationalProtocol(&game, 1, NO_PLAYER)
	testing.expect(t, ok)
	testing.expect_value(t, observation.kind, ObservationKind.Deck)
	testing.expect_value(t, observation.count, 1)
	testing.expect_value(t, observation.cardIds[0], top)
	testing.expect(t, FinishInformationalProtocol(&game, {option = true}))
	testing.expect_value(t, game.players[0].hand[2], second)
	testing.expect_value(t, game.players[0].deck[0], top)
}
