#+build !js

package server

import "core:testing"

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
