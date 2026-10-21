-- v0.6: "Who is coming?" and the team khata (expenses and who paid).

CREATE TABLE IF NOT EXISTS asks (
  id TEXT PRIMARY KEY,
  scorer_id TEXT NOT NULL,
  team_id TEXT NOT NULL,
  title TEXT NOT NULL,
  when_text TEXT NOT NULL DEFAULT '',
  place TEXT NOT NULL DEFAULT '',
  need INTEGER NOT NULL DEFAULT 11,
  user_id TEXT NOT NULL,
  created INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS asks_team ON asks(scorer_id, team_id, created);

CREATE TABLE IF NOT EXISTS ask_replies (
  ask_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  answer TEXT NOT NULL,       -- yes, no, maybe
  user_id TEXT NOT NULL,
  updated INTEGER NOT NULL,
  PRIMARY KEY (ask_id, player_id)
);

CREATE TABLE IF NOT EXISTS khata (
  id TEXT PRIMARY KEY,
  scorer_id TEXT NOT NULL,
  team_id TEXT NOT NULL,
  month TEXT NOT NULL,        -- YYYY-MM
  kind TEXT NOT NULL,         -- expense (someone spent for the team) or payment (someone paid their share)
  amount INTEGER NOT NULL,    -- rupees
  note TEXT NOT NULL DEFAULT '',
  player_id TEXT NOT NULL,    -- who spent / who paid
  user_id TEXT NOT NULL,
  created INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS khata_team ON khata(scorer_id, team_id, month);
