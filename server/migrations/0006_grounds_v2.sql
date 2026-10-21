-- v0.8: richer grounds (photos, reviews, facilities, fees) and matches linked to a ground.
ALTER TABLE grounds ADD COLUMN city TEXT NOT NULL DEFAULT '';
ALTER TABLE grounds ADD COLUMN pitches TEXT NOT NULL DEFAULT '[]';     -- ["turf","matting"]
ALTER TABLE grounds ADD COLUMN facilities TEXT NOT NULL DEFAULT '[]';  -- ["lights","washrooms",...]
ALTER TABLE grounds ADD COLUMN fee_min INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grounds ADD COLUMN fee_max INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grounds ADD COLUMN boundary_min INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grounds ADD COLUMN boundary_max INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grounds ADD COLUMN timings TEXT NOT NULL DEFAULT '';
ALTER TABLE grounds ADD COLUMN phone2 TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS ground_photos (
  id TEXT PRIMARY KEY,
  ground_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  data TEXT NOT NULL,          -- base64 JPEG (kept small by the app)
  created INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ground_photos_ground ON ground_photos(ground_id, created);

CREATE TABLE IF NOT EXISTS ground_reviews (
  ground_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  stars INTEGER NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  created INTEGER NOT NULL,
  PRIMARY KEY (ground_id, user_id)
);

ALTER TABLE matches ADD COLUMN ground_id TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS matches_ground ON matches(ground_id, updated);
