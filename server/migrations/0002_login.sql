-- Player login with Google. Mobile numbers are never stored as numbers:
-- only a keyed hash (HMAC with a random key kept in "config") is kept, so
-- the server can match "same number" without being able to read it.
CREATE TABLE IF NOT EXISTS config (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);

-- Mobile numbers scorers typed for their players (hashed).
CREATE TABLE IF NOT EXISTS player_phones (
  scorer_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  phone_hash TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  team TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (scorer_id, player_id)
);
CREATE INDEX IF NOT EXISTS player_phones_hash ON player_phones(phone_hash);

-- People who logged in with Google.
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  phone_hash TEXT,
  created INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS users_phone ON users(phone_hash);

-- One row per logged-in phone (only the token's hash is kept).
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created INTEGER NOT NULL
);

-- "This player profile is me": pending until the scorer says yes.
CREATE TABLE IF NOT EXISTS claims (
  user_id TEXT NOT NULL,
  scorer_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created INTEGER NOT NULL,
  PRIMARY KEY (user_id, scorer_id, player_id)
);
CREATE INDEX IF NOT EXISTS claims_scorer ON claims(scorer_id, status);
