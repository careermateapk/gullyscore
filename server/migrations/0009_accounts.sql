-- v1.1: sign up with email and password (or Google), with mobile, state and city.
ALTER TABLE users ADD COLUMN pass_hash TEXT NOT NULL DEFAULT '';   -- PBKDF2, never the password itself
ALTER TABLE users ADD COLUMN pass_salt TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN phone_code TEXT NOT NULL DEFAULT '';  -- e.g. +91
ALTER TABLE users ADD COLUMN state TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN city TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN terms_at INTEGER NOT NULL DEFAULT 0;  -- when they agreed to the terms
CREATE INDEX IF NOT EXISTS users_email ON users(email);

-- Wrong password tries, to slow down guessing.
CREATE TABLE IF NOT EXISTS login_fails (
  email TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS login_fails_email ON login_fails(email, at);
