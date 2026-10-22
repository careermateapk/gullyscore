-- v0.9: ground booking. The owner lists time slots; teams send requests.
CREATE TABLE IF NOT EXISTS ground_slots (
  id TEXT PRIMARY KEY,
  ground_id TEXT NOT NULL,
  label TEXT NOT NULL DEFAULT '',     -- e.g. "Morning"
  start_min INTEGER NOT NULL,         -- minutes after midnight
  end_min INTEGER NOT NULL,
  price INTEGER NOT NULL DEFAULT 0,   -- rupees
  days INTEGER NOT NULL DEFAULT 127,  -- bit 0 Monday … bit 6 Sunday
  sort INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ground_slots_ground ON ground_slots(ground_id, sort);

CREATE TABLE IF NOT EXISTS bookings (
  id TEXT PRIMARY KEY,
  ground_id TEXT NOT NULL,
  slot_id TEXT NOT NULL,
  date TEXT NOT NULL,                 -- YYYY-MM-DD (India)
  user_id TEXT NOT NULL,
  team TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',     -- shown only to the ground's owner
  note TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'requested', -- requested, accepted, declined, cancelled
  created INTEGER NOT NULL,
  updated INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS bookings_ground ON bookings(ground_id, date);
CREATE INDEX IF NOT EXISTS bookings_user ON bookings(user_id, created);
