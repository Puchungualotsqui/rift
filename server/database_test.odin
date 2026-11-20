#+build !js

package server

import sqlite "../odin-sqlite3"
import "core:testing"
import "core:strings"

@(test)
TestGuestSessionLifecycle :: proc(t: ^testing.T) {
	database: Database
	testing.expect(t, DatabaseInit(&database, ":memory:"))
	defer DatabaseDeinit(&database)

	session, created := DatabaseCreateGuestSession(&database)
	testing.expect(t, created)
	testing.expect(t, len(session.sessionToken) == 64)
	testing.expect(t, session.playerId > 0)
	testing.expect(t, session.expiresAt > 0)

	profile, authenticated := DatabaseAuthenticate(&database, session.sessionToken)
	testing.expect(t, authenticated)
	testing.expect_value(t, profile.playerId, session.playerId)
	testing.expect_value(t, profile.displayName, session.displayName)
	testing.expect_value(t, profile.gamesPlayed, i64(0))
	testing.expect_value(t, profile.wins, i64(0))

	_, authenticated = DatabaseAuthenticate(&database, "not-a-session-token")
	testing.expect(t, !authenticated)
	testing.expect(t, DatabaseRevokeSession(&database, session.sessionToken))
	_, authenticated = DatabaseAuthenticate(&database, session.sessionToken)
	testing.expect(t, !authenticated)
}

@(test)
TestMatchPersistenceLifecycle :: proc(t: ^testing.T) {
	database: Database
	testing.expect(t, DatabaseInit(&database, ":memory:"))
	defer DatabaseDeinit(&database)

	first, firstCreated := DatabaseCreateGuestSession(&database)
	second, secondCreated := DatabaseCreateGuestSession(&database)
	testing.expect(t, firstCreated && secondCreated)

	seed := u64(0xfedcba9876543210)
	matchParticipants := [?]DatabaseMatchParticipant{
		{playerId = first.playerId, faction = "Nomad"},
		{playerId = second.playerId, faction = "Swarm"},
	}
	matchId, started := DatabaseStartMatch(&database, seed, matchParticipants[:])
	testing.expect(t, started)
	testing.expect(t, matchId > 0)

	stmt: ^sqlite.Statement
	defer if stmt != nil do sqlite.finalize(stmt)
	if DatabasePrepare(&database, &stmt, "SELECT started_at, COALESCE(ended_at, 0), seed, COALESCE(winner_player, 0) FROM matches WHERE match_id = ?;") {
		if DatabaseBindInt64(stmt, 1, matchId) && sqlite.step(stmt) == .Row {
			testing.expect(t, sqlite.column_int64(stmt, 0) > 0)
			testing.expect_value(t, sqlite.column_int64(stmt, 1), i64(0))
			testing.expect_value(t, cast(u64)sqlite.column_int64(stmt, 2), seed)
			testing.expect_value(t, sqlite.column_int64(stmt, 3), i64(0))
		} else {
			testing.expect(t, false)
		}
	} else {
		testing.expect(t, false)
	}
	sqlite.finalize(stmt)
	stmt = nil

	if DatabasePrepare(&database, &stmt, "SELECT player_id, faction FROM match_players WHERE match_id = ? ORDER BY player_id;") {
		if DatabaseBindInt64(stmt, 1, matchId) && sqlite.step(stmt) == .Row {
			testing.expect_value(t, sqlite.column_int64(stmt, 0), first.playerId)
			testing.expect_value(t, strings.clone_from(sqlite.column_text(stmt, 1), context.temp_allocator), "Nomad")
		} else {
			testing.expect(t, false)
		}
		if sqlite.step(stmt) == .Row {
			testing.expect_value(t, sqlite.column_int64(stmt, 0), second.playerId)
			testing.expect_value(t, strings.clone_from(sqlite.column_text(stmt, 1), context.temp_allocator), "Swarm")
		} else {
			testing.expect(t, false)
		}
		testing.expect(t, sqlite.step(stmt) == .Done)
	} else {
		testing.expect(t, false)
	}
	sqlite.finalize(stmt)
	stmt = nil

	results := [?]DatabaseMatchPlayerResult{
		{playerId = first.playerId, faction = "Nomad", publicVp = 3, factionVp = 4, directiveVp = 2, totalVp = 9, winner = true},
		{playerId = second.playerId, faction = "Swarm", publicVp = 1, factionVp = 2, directiveVp = 3, totalVp = 6, winner = false},
	}
	testing.expect(t, DatabaseFinishMatch(&database, matchId, first.playerId, results[:]))

	if DatabasePrepare(&database, &stmt, "SELECT ended_at, winner_player FROM matches WHERE match_id = ?;") {
		if DatabaseBindInt64(stmt, 1, matchId) && sqlite.step(stmt) == .Row {
			testing.expect(t, sqlite.column_int64(stmt, 0) > 0)
			testing.expect_value(t, sqlite.column_int64(stmt, 1), first.playerId)
		} else {
			testing.expect(t, false)
		}
	} else {
		testing.expect(t, false)
	}
	sqlite.finalize(stmt)
	stmt = nil

	if DatabasePrepare(&database, &stmt, "SELECT mp.player_id, mp.public_vp, mp.faction_vp, mp.directive_vp, mp.total_vp, ps.games_played, ps.wins FROM match_players AS mp JOIN player_stats AS ps ON ps.player_id = mp.player_id WHERE mp.match_id = ? ORDER BY mp.player_id;") {
		if DatabaseBindInt64(stmt, 1, matchId) && sqlite.step(stmt) == .Row {
			testing.expect_value(t, sqlite.column_int64(stmt, 0), first.playerId)
			testing.expect_value(t, sqlite.column_int64(stmt, 1), i64(3))
			testing.expect_value(t, sqlite.column_int64(stmt, 2), i64(4))
			testing.expect_value(t, sqlite.column_int64(stmt, 3), i64(2))
			testing.expect_value(t, sqlite.column_int64(stmt, 4), i64(9))
			testing.expect_value(t, sqlite.column_int64(stmt, 5), i64(1))
			testing.expect_value(t, sqlite.column_int64(stmt, 6), i64(1))
		} else {
			testing.expect(t, false)
		}
		if sqlite.step(stmt) == .Row {
			testing.expect_value(t, sqlite.column_int64(stmt, 0), second.playerId)
			testing.expect_value(t, sqlite.column_int64(stmt, 1), i64(1))
			testing.expect_value(t, sqlite.column_int64(stmt, 2), i64(2))
			testing.expect_value(t, sqlite.column_int64(stmt, 3), i64(3))
			testing.expect_value(t, sqlite.column_int64(stmt, 4), i64(6))
			testing.expect_value(t, sqlite.column_int64(stmt, 5), i64(1))
			testing.expect_value(t, sqlite.column_int64(stmt, 6), i64(0))
		} else {
			testing.expect(t, false)
		}
		testing.expect(t, sqlite.step(stmt) == .Done)
	} else {
		testing.expect(t, false)
	}
}

@(test)
TestMatchPersistenceRollback :: proc(t: ^testing.T) {
	database: Database
	testing.expect(t, DatabaseInit(&database, ":memory:"))
	defer DatabaseDeinit(&database)

	first, created := DatabaseCreateGuestSession(&database)
	testing.expect(t, created)
	participants := [?]DatabaseMatchParticipant{{playerId = first.playerId, faction = "Nomad"}}
	matchId, started := DatabaseStartMatch(&database, 1, participants[:])
	testing.expect(t, started)


	results := [?]DatabaseMatchPlayerResult{
		{playerId = first.playerId, faction = "Nomad", publicVp = 5, factionVp = 4, directiveVp = 3, totalVp = 12, winner = true},
		{playerId = 999999999, faction = "Unknown", publicVp = 1, factionVp = 1, directiveVp = 1, totalVp = 3, winner = false},
	}
	testing.expect(t, !DatabaseFinishMatch(&database, matchId, first.playerId, results[:]))

	stmt: ^sqlite.Statement
	defer if stmt != nil do sqlite.finalize(stmt)
	if DatabasePrepare(&database, &stmt, "SELECT COALESCE(ended_at, 0), COALESCE(winner_player, 0) FROM matches WHERE match_id = ?;") {
		if DatabaseBindInt64(stmt, 1, matchId) && sqlite.step(stmt) == .Row {
			testing.expect_value(t, sqlite.column_int64(stmt, 0), i64(0))
			testing.expect_value(t, sqlite.column_int64(stmt, 1), i64(0))
		} else {
			testing.expect(t, false)
		}
	} else {
		testing.expect(t, false)
	}
	sqlite.finalize(stmt)
	stmt = nil

	if DatabasePrepare(&database, &stmt, "SELECT public_vp, faction_vp, directive_vp, total_vp, ps.games_played, ps.wins FROM match_players AS mp JOIN player_stats AS ps ON ps.player_id = mp.player_id WHERE mp.match_id = ? AND mp.player_id = ?;") {
		if DatabaseBindInt64(stmt, 1, matchId) && DatabaseBindInt64(stmt, 2, first.playerId) && sqlite.step(stmt) == .Row {
			testing.expect_value(t, sqlite.column_int64(stmt, 0), i64(0))
			testing.expect_value(t, sqlite.column_int64(stmt, 1), i64(0))
			testing.expect_value(t, sqlite.column_int64(stmt, 2), i64(0))
			testing.expect_value(t, sqlite.column_int64(stmt, 3), i64(0))
			testing.expect_value(t, sqlite.column_int64(stmt, 4), i64(0))
			testing.expect_value(t, sqlite.column_int64(stmt, 5), i64(0))
		} else {
			testing.expect(t, false)
		}
	} else {
		testing.expect(t, false)
	}
}
