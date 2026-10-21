-- v0.5: all-matches feed, My Cricket, leaderboard, community, ratings.

-- Matches: status for the feed, schedule, ground, teams and winner.
ALTER TABLE matches ADD COLUMN status TEXT NOT NULL DEFAULT 'live'; -- upcoming, live, result
ALTER TABLE matches ADD COLUMN scheduled INTEGER;                   -- ms, for upcoming matches
ALTER TABLE matches ADD COLUMN ground TEXT NOT NULL DEFAULT '';
ALTER TABLE matches ADD COLUMN team_a TEXT NOT NULL DEFAULT '';      -- team ids on the scorer's phone
ALTER TABLE matches ADD COLUMN team_b TEXT NOT NULL DEFAULT '';
ALTER TABLE matches ADD COLUMN team_a_name TEXT NOT NULL DEFAULT '';
ALTER TABLE matches ADD COLUMN team_b_name TEXT NOT NULL DEFAULT '';
ALTER TABLE matches ADD COLUMN winner TEXT NOT NULL DEFAULT '';      -- team id, 'tie' or ''
CREATE INDEX IF NOT EXISTS matches_status ON matches(status, updated);
CREATE INDEX IF NOT EXISTS matches_scheduled ON matches(status, scheduled);

-- Each player's numbers in a match (for My Cricket and the leaderboard).
ALTER TABLE match_players ADD COLUMN team TEXT NOT NULL DEFAULT '';
ALTER TABLE match_players ADD COLUMN name TEXT NOT NULL DEFAULT '';
ALTER TABLE match_players ADD COLUMN runs INTEGER NOT NULL DEFAULT 0;
ALTER TABLE match_players ADD COLUMN wickets INTEGER NOT NULL DEFAULT 0;
ALTER TABLE match_players ADD COLUMN line TEXT NOT NULL DEFAULT '{}';

-- Which team a player with a mobile number plays for.
ALTER TABLE player_phones ADD COLUMN team_id TEXT NOT NULL DEFAULT '';

-- Community posts: need players, find opponent, poll, tournament, general.
CREATE TABLE IF NOT EXISTS posts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  body TEXT NOT NULL,
  place TEXT NOT NULL DEFAULT '',
  extra TEXT NOT NULL DEFAULT '{}',   -- poll options / tournament details
  contact TEXT NOT NULL DEFAULT '',   -- WhatsApp number, shown only to people who joined
  created INTEGER NOT NULL,
  hidden INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS posts_created ON posts(hidden, created);

CREATE TABLE IF NOT EXISTS post_joins (
  post_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',      -- e.g. team name when registering for a tournament
  paid INTEGER NOT NULL DEFAULT 0,    -- organiser ticks after receiving the entry fee
  created INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS poll_votes (
  post_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  option INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

-- Ratings: one per person, per match, for the other team.
CREATE TABLE IF NOT EXISTS ratings (
  match_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  scorer_id TEXT NOT NULL,
  team_id TEXT NOT NULL,
  fair INTEGER NOT NULL,
  behaviour INTEGER NOT NULL,
  ontime INTEGER NOT NULL,
  tags TEXT NOT NULL DEFAULT '[]',
  created INTEGER NOT NULL,
  PRIMARY KEY (match_id, user_id, team_id)
);
CREATE INDEX IF NOT EXISTS ratings_team ON ratings(scorer_id, team_id);

-- Comments on a team (with a rating) and replies to them.
CREATE TABLE IF NOT EXISTS comments (
  id TEXT PRIMARY KEY,
  scorer_id TEXT NOT NULL,
  team_id TEXT NOT NULL,
  match_id TEXT NOT NULL DEFAULT '',
  parent_id TEXT NOT NULL DEFAULT '',
  user_id TEXT NOT NULL,
  author_team TEXT NOT NULL DEFAULT '',
  is_team INTEGER NOT NULL DEFAULT 0,   -- written by a player of the rated team
  stars REAL NOT NULL DEFAULT 0,
  body TEXT NOT NULL,
  created INTEGER NOT NULL,
  hidden INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS comments_team ON comments(scorer_id, team_id, parent_id, created);
CREATE INDEX IF NOT EXISTS comments_parent ON comments(parent_id, created);

CREATE TABLE IF NOT EXISTS reactions (
  comment_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  emoji TEXT NOT NULL,
  PRIMARY KEY (comment_id, user_id)
);

CREATE TABLE IF NOT EXISTS reports (
  kind TEXT NOT NULL,       -- post or comment
  target_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created INTEGER NOT NULL,
  PRIMARY KEY (kind, target_id, user_id)
);
