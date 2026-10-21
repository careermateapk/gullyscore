-- Scorers are phones. Each gets a secret token; only the hash is kept.
CREATE TABLE IF NOT EXISTS scorers (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  created INTEGER NOT NULL
);

-- One row per match. "data" is everything the app needs to show it;
-- "summary" is a small scorecard for the web page and lists.
CREATE TABLE IF NOT EXISTS matches (
  id TEXT PRIMARY KEY,
  scorer_id TEXT NOT NULL,
  updated INTEGER NOT NULL,
  finished INTEGER NOT NULL DEFAULT 0,
  title TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL,
  data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS matches_updated ON matches(updated);

-- Which players were in which match, so a player can find their matches.
CREATE TABLE IF NOT EXISTS match_players (
  match_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  PRIMARY KEY (match_id, player_id)
);
CREATE INDEX IF NOT EXISTS match_players_player ON match_players(player_id);

-- Invite codes that link a player's own phone to their profile.
CREATE TABLE IF NOT EXISTS invites (
  code TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  name TEXT NOT NULL,
  team TEXT NOT NULL DEFAULT '',
  scorer_id TEXT NOT NULL,
  created INTEGER NOT NULL
);
