package server

import sqlite "../odin-sqlite3"
import "core:crypto"
import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:sync"
import "core:time"

SESSION_LIFETIME_SECONDS :: 24 * 60 * 60
GUEST_TOKEN_LIFETIME_SECONDS :: 60 * 60

Database :: struct {
	connection: ^sqlite.Connection,
	mutex:      sync.Mutex,
}

GuestSession :: struct {
	sessionToken: string,
	playerId:     i64,
	displayName:  string,
	expiresAt:    i64,
}

PlayerProfile :: struct {
	playerId:    i64    `json:"player_id"`,
	displayName: string `json:"display_name"`,
	gamesPlayed: i64    `json:"games_played"`,
	wins:        i64    `json:"wins"`,
}

DatabaseMatchParticipant :: struct {
	playerId: i64,
	faction:  string,
}

DatabaseMatchPlayerResult :: struct {
	playerId:   i64,
	faction:    string,
	publicVp:   int,
	factionVp:  int,
	directiveVp: int,
	totalVp:    int,
	winner:     bool,
}

DatabaseInit :: proc(database: ^Database, path: cstring) -> bool {
	if result := sqlite.open(path, &database.connection); result != .Ok {
		if database.connection != nil do sqlite.close(database.connection)
		log.errorf("Could not open the SQLite database: %v", result)
		return false
	}

	if !DatabaseExecute(database, "PRAGMA journal_mode=WAL;") ||
		!DatabaseExecute(database, "PRAGMA foreign_keys=ON;") ||
		!DatabaseExecute(database, "PRAGMA busy_timeout=5000;") {
		DatabaseDeinit(database)
		return false
	}

	for statement in DATABASE_SCHEMA {
		if !DatabaseExecute(database, statement) {
			DatabaseDeinit(database)
			return false
		}
	}

	return true
}

DatabaseDeinit :: proc(database: ^Database) {
	if database.connection != nil {
		sqlite.close(database.connection)
		database.connection = nil
	}
}

DatabaseCreateGuestSession :: proc(database: ^Database) -> (session: GuestSession, ok: bool) {
	guestUid := DatabaseRandomToken()
	guestToken := DatabaseRandomToken()
	sessionToken := DatabaseRandomToken()
	now := time.to_unix_seconds(time.now())
	expiresAt := now + SESSION_LIFETIME_SECONDS
	guestTokenExpiresAt := now + GUEST_TOKEN_LIFETIME_SECONDS

	sync.lock(&database.mutex)
	defer sync.unlock(&database.mutex)

	if !DatabaseExecute(database, "BEGIN IMMEDIATE;") do return
	committed := false
	defer if !committed do DatabaseExecute(database, "ROLLBACK;")

	stmt: ^sqlite.Statement
	if !DatabasePrepare(database, &stmt, "INSERT INTO players (display_name, created_at, last_seen_at) VALUES ('Guest', ?, ?);") do return
	defer {
		if stmt != nil do sqlite.finalize(stmt)
	}
	if !DatabaseBindInt64(stmt, 1, now) || !DatabaseBindInt64(stmt, 2, now) || !DatabaseStepDone(database, stmt) do return
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabasePrepare(database, &stmt, "SELECT last_insert_rowid();") do return
	if sqlite.step(stmt) != .Row {
		DatabaseLogError(database, "Could not get the new player ID")
		return
	}
	playerId := sqlite.column_int64(stmt, 0)
	sqlite.finalize(stmt)
	stmt = nil

	displayName := fmt.tprintf("Guest %d", playerId)
	if !DatabasePrepare(database, &stmt, "UPDATE players SET display_name = ? WHERE player_id = ?;") do return
	if !DatabaseBindText(stmt, 1, displayName) || !DatabaseBindInt64(stmt, 2, playerId) || !DatabaseStepDone(database, stmt) do return
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabasePrepare(database, &stmt, "INSERT INTO auth_identities (player_id, provider, provider_uid, created_at) VALUES (?, 'guest', ?, ?);") do return
	if !DatabaseBindInt64(stmt, 1, playerId) || !DatabaseBindText(stmt, 2, guestUid) ||
		!DatabaseBindInt64(stmt, 3, now) || !DatabaseStepDone(database, stmt) {
		return
	}
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabasePrepare(database, &stmt, "INSERT INTO guest_tokens (token, player_id, expires_at, created_at) VALUES (?, ?, ?, ?);") do return
	if !DatabaseBindText(stmt, 1, guestToken) || !DatabaseBindInt64(stmt, 2, playerId) ||
		!DatabaseBindInt64(stmt, 3, guestTokenExpiresAt) || !DatabaseBindInt64(stmt, 4, now) ||
		!DatabaseStepDone(database, stmt) {
		return
	}
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabasePrepare(database, &stmt, "INSERT INTO sessions (session_token, player_id, platform, expires_at, created_at) VALUES (?, ?, 'web', ?, ?);") do return
	if !DatabaseBindText(stmt, 1, sessionToken) || !DatabaseBindInt64(stmt, 2, playerId) ||
		!DatabaseBindInt64(stmt, 3, expiresAt) || !DatabaseBindInt64(stmt, 4, now) ||
		!DatabaseStepDone(database, stmt) {
		return
	}
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabasePrepare(database, &stmt, "INSERT INTO player_stats (player_id) VALUES (?);") do return
	if !DatabaseBindInt64(stmt, 1, playerId) || !DatabaseStepDone(database, stmt) do return
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabaseExecute(database, "COMMIT;") do return
	committed = true
	session = GuestSession{sessionToken, playerId, displayName, expiresAt}
	ok = true
	return
}

DatabaseAuthenticate :: proc(database: ^Database, token: string) -> (profile: PlayerProfile, ok: bool) {
	sync.lock(&database.mutex)
	defer sync.unlock(&database.mutex)

	stmt: ^sqlite.Statement
	if !DatabasePrepare(
		database,
		&stmt,
		"SELECT p.player_id, p.display_name, COALESCE(s.games_played, 0), COALESCE(s.wins, 0) FROM sessions AS a JOIN players AS p ON p.player_id = a.player_id LEFT JOIN player_stats AS s ON s.player_id = p.player_id WHERE a.session_token = ? AND a.expires_at > ?;",
	) {
		return
	}
	if !DatabaseBindText(stmt, 1, token) ||
		!DatabaseBindInt64(stmt, 2, time.to_unix_seconds(time.now())) {
		sqlite.finalize(stmt)
		return
	}

	stepResult := sqlite.step(stmt)
	if stepResult != .Row {
		if stepResult != .Done do DatabaseLogError(database, "Could not look up session")
		sqlite.finalize(stmt)
		return
	}
	profile.playerId = sqlite.column_int64(stmt, 0)
	profile.displayName = strings.clone_from(sqlite.column_text(stmt, 1), context.temp_allocator)
	profile.gamesPlayed = sqlite.column_int64(stmt, 2)
	profile.wins = sqlite.column_int64(stmt, 3)
	sqlite.finalize(stmt)

	stmt = nil
	if !DatabasePrepare(database, &stmt, "UPDATE players SET last_seen_at = ? WHERE player_id = ?;") do return
	defer sqlite.finalize(stmt)
	if !DatabaseBindInt64(stmt, 1, time.to_unix_seconds(time.now())) ||
		!DatabaseBindInt64(stmt, 2, profile.playerId) || !DatabaseStepDone(database, stmt) {
		profile = {}
		return
	}

	ok = true
	return
}

DatabaseRevokeSession :: proc(database: ^Database, token: string) -> bool {
	sync.lock(&database.mutex)
	defer sync.unlock(&database.mutex)

	stmt: ^sqlite.Statement
	if !DatabasePrepare(database, &stmt, "DELETE FROM sessions WHERE session_token = ?;") do return false
	defer sqlite.finalize(stmt)
	return DatabaseBindText(stmt, 1, token) && DatabaseStepDone(database, stmt)
}

DatabaseStartMatch :: proc(database: ^Database, seed: u64, participants: []DatabaseMatchParticipant) -> (matchId: i64, ok: bool) {
	sync.lock(&database.mutex)
	defer sync.unlock(&database.mutex)

	if !DatabaseExecute(database, "BEGIN IMMEDIATE;") do return
	committed := false
	defer if !committed do DatabaseExecute(database, "ROLLBACK;")

	stmt: ^sqlite.Statement
	defer if stmt != nil do sqlite.finalize(stmt)

	now := time.to_unix_seconds(time.now())
	if !DatabasePrepare(database, &stmt, "INSERT INTO matches (started_at, seed) VALUES (?, ?);") do return
	if !DatabaseBindInt64(stmt, 1, now) || !DatabaseBindInt64(stmt, 2, transmute(i64)seed) || !DatabaseStepDone(database, stmt) do return
	sqlite.finalize(stmt)
	stmt = nil

	if !DatabasePrepare(database, &stmt, "SELECT last_insert_rowid();") do return
	if sqlite.step(stmt) != .Row {
		DatabaseLogError(database, "Could not get the new match ID")
		return
	}
	newMatchId := sqlite.column_int64(stmt, 0)
	sqlite.finalize(stmt)
	stmt = nil

	for participant in participants {
		if !DatabasePrepare(database, &stmt, "INSERT INTO match_players (match_id, player_id, faction) VALUES (?, ?, ?);") do return
		if !DatabaseBindInt64(stmt, 1, newMatchId) || !DatabaseBindInt64(stmt, 2, participant.playerId) ||
			!DatabaseBindText(stmt, 3, participant.faction) || !DatabaseStepDone(database, stmt) {
			return
		}
		sqlite.finalize(stmt)
		stmt = nil
	}

	if !DatabaseExecute(database, "COMMIT;") do return
	committed = true
	matchId = newMatchId
	ok = true
	return
}

DatabaseFinishMatch :: proc(database: ^Database, matchId: i64, winnerPlayerId: i64, participants: []DatabaseMatchPlayerResult) -> bool {
	sync.lock(&database.mutex)
	defer sync.unlock(&database.mutex)

	if !DatabaseExecute(database, "BEGIN IMMEDIATE;") do return false
	committed := false
	defer if !committed do DatabaseExecute(database, "ROLLBACK;")

	now := time.to_unix_seconds(time.now())
	stmt: ^sqlite.Statement
	if !DatabasePrepare(database, &stmt, "UPDATE matches SET ended_at = ?, winner_player = ? WHERE match_id = ?;") do return false
	if !DatabaseBindInt64(stmt, 1, now) || !DatabaseBindInt64(stmt, 2, winnerPlayerId) ||
		!DatabaseBindInt64(stmt, 3, matchId) || !DatabaseStepDone(database, stmt) {
		sqlite.finalize(stmt)
		return false
	}
	if sqlite.changes(database.connection) != 1 {
		sqlite.finalize(stmt)
		return false
	}
	sqlite.finalize(stmt)

	for participant in participants {
		stmt = nil
		if !DatabasePrepare(database, &stmt, "UPDATE match_players SET public_vp = ?, faction_vp = ?, directive_vp = ?, total_vp = ? WHERE match_id = ? AND player_id = ?;") do return false
		if !DatabaseBindInt64(stmt, 1, i64(participant.publicVp)) || !DatabaseBindInt64(stmt, 2, i64(participant.factionVp)) ||
			!DatabaseBindInt64(stmt, 3, i64(participant.directiveVp)) || !DatabaseBindInt64(stmt, 4, i64(participant.totalVp)) ||
			!DatabaseBindInt64(stmt, 5, matchId) || !DatabaseBindInt64(stmt, 6, participant.playerId) ||
			!DatabaseStepDone(database, stmt) {
			sqlite.finalize(stmt)
			return false
		}
		if sqlite.changes(database.connection) != 1 {
			sqlite.finalize(stmt)
			return false
		}
		sqlite.finalize(stmt)

		stmt = nil
		if !DatabasePrepare(database, &stmt, "UPDATE player_stats SET games_played = games_played + 1, wins = wins + ? WHERE player_id = ?;") do return false
		winnerIncrement: i64 = 0
		if participant.winner do winnerIncrement = 1
		if !DatabaseBindInt64(stmt, 1, winnerIncrement) || !DatabaseBindInt64(stmt, 2, participant.playerId) || !DatabaseStepDone(database, stmt) {
			sqlite.finalize(stmt)
			return false
		}
		if sqlite.changes(database.connection) != 1 {
			sqlite.finalize(stmt)
			return false
		}
		sqlite.finalize(stmt)
	}

	if !DatabaseExecute(database, "COMMIT;") do return false
	committed = true
	return true
}

DatabaseRandomToken :: proc() -> string {
	TOKEN_BYTES :: 32
	hexDigits := "0123456789abcdef"
	bytes: [TOKEN_BYTES]byte
	crypto.rand_bytes(bytes[:])

	token := make([]byte, TOKEN_BYTES * 2, context.temp_allocator)
	for value, i in bytes {
		token[i * 2] = hexDigits[value >> 4]
		token[i * 2 + 1] = hexDigits[value & 0x0f]
	}
	return string(token)
}

DatabaseExecute :: proc(database: ^Database, statement: cstring) -> bool {
	if result := sqlite.exec(database.connection, statement, nil, nil, nil); result != .Ok {
		DatabaseLogError(database, "SQLite statement failed")
		return false
	}
	return true
}

DatabasePrepare :: proc(database: ^Database, statement: ^^sqlite.Statement, query: cstring) -> bool {
	if result := sqlite.prepare_v2(database.connection, query, -1, statement, nil); result != .Ok {
		DatabaseLogError(database, "Could not prepare SQLite statement")
		return false
	}
	return true
}

DatabaseBindText :: proc(statement: ^sqlite.Statement, index: int, value: string) -> bool {
	cString, err := strings.clone_to_cstring(value, context.temp_allocator)
	if err != nil do return false
	return sqlite.bind_text(
		statement,
		c.int(index),
		cString,
		c.int(len(value)),
		sqlite.Destructor{behaviour = .Transient},
	) == .Ok
}

DatabaseBindInt64 :: proc(statement: ^sqlite.Statement, index: int, value: i64) -> bool {
	return sqlite.bind_int64(statement, c.int(index), c.int64_t(value)) == .Ok
}

DatabaseStepDone :: proc(database: ^Database, statement: ^sqlite.Statement) -> bool {
	if sqlite.step(statement) != .Done {
		DatabaseLogError(database, "SQLite mutation failed")
		return false
	}
	return true
}

DatabaseLogError :: proc(database: ^Database, message: string) {
	log.errorf("%s: %s", message, sqlite.errmsg(database.connection))
}

DATABASE_SCHEMA :: [?]cstring{
	"CREATE TABLE IF NOT EXISTS players (player_id INTEGER PRIMARY KEY AUTOINCREMENT, display_name TEXT NOT NULL, created_at INTEGER NOT NULL, last_seen_at INTEGER NOT NULL);",
	"CREATE TABLE IF NOT EXISTS auth_identities (identity_id INTEGER PRIMARY KEY AUTOINCREMENT, player_id INTEGER NOT NULL REFERENCES players(player_id), provider TEXT NOT NULL, provider_uid TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(provider, provider_uid));",
	"CREATE INDEX IF NOT EXISTS idx_auth_player ON auth_identities(player_id);",
	"CREATE TABLE IF NOT EXISTS guest_tokens (token TEXT PRIMARY KEY, player_id INTEGER NOT NULL REFERENCES players(player_id), expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL);",
	"CREATE TABLE IF NOT EXISTS sessions (session_token TEXT PRIMARY KEY, player_id INTEGER NOT NULL REFERENCES players(player_id), platform TEXT NOT NULL, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL);",
	"CREATE INDEX IF NOT EXISTS idx_sessions_player ON sessions(player_id);",
	"CREATE TABLE IF NOT EXISTS matches (match_id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER, winner_player INTEGER REFERENCES players(player_id), seed INTEGER NOT NULL, state_blob BLOB);",
	"CREATE TABLE IF NOT EXISTS match_players (match_id INTEGER NOT NULL REFERENCES matches(match_id), player_id INTEGER NOT NULL REFERENCES players(player_id), faction TEXT NOT NULL, public_vp INTEGER NOT NULL DEFAULT 0, faction_vp INTEGER NOT NULL DEFAULT 0, directive_vp INTEGER NOT NULL DEFAULT 0, total_vp INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (match_id, player_id));",
	"CREATE TABLE IF NOT EXISTS player_stats (player_id INTEGER PRIMARY KEY REFERENCES players(player_id), games_played INTEGER NOT NULL DEFAULT 0, wins INTEGER NOT NULL DEFAULT 0, faction_stats TEXT NOT NULL DEFAULT '{}');",
}
