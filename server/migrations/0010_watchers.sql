-- Who is watching a match's live video in the app right now (anonymous phone ids).
CREATE TABLE IF NOT EXISTS watchers (
  match_id TEXT NOT NULL,
  device TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (match_id, device)
);
CREATE INDEX IF NOT EXISTS watchers_at ON watchers(at);
