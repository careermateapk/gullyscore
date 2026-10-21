-- v0.7: cricket grounds (added by users, or picked from a Google search).
CREATE TABLE IF NOT EXISTS grounds (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT NOT NULL DEFAULT '',
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  place_id TEXT NOT NULL DEFAULT '',   -- Google place id when it came from Google
  pitch TEXT NOT NULL DEFAULT '',      -- turf, matting, cement, mud
  fee TEXT NOT NULL DEFAULT '',        -- free text, e.g. "₹1,500 / match" or "Free"
  phone TEXT NOT NULL DEFAULT '',
  lights INTEGER NOT NULL DEFAULT 0,
  toilet INTEGER NOT NULL DEFAULT 0,
  user_id TEXT NOT NULL,
  created INTEGER NOT NULL,
  hidden INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS grounds_lat ON grounds(lat, lng);
CREATE INDEX IF NOT EXISTS grounds_place ON grounds(place_id);
