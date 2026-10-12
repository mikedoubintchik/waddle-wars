-- One row per (user, mode, course); value is ms for mode='time' (lower is
-- better), or points for mode='endless'/'runner' (higher is better).
CREATE TABLE IF NOT EXISTS scores (
  user_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'Penguin',
  mode TEXT NOT NULL,
  course TEXT NOT NULL,
  value INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, mode, course)
);
CREATE INDEX IF NOT EXISTS idx_scores_board ON scores (mode, course, value);

-- Explicitly chosen public game handle; private Clerk names are not published.
CREATE TABLE IF NOT EXISTS profiles (
  user_id TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

-- Cloud save blobs (whole save.json, small).
CREATE TABLE IF NOT EXISTS saves (
  user_id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Required by active-subject authentication. Existing deployments apply
-- migration 0006 before deploying account-lifecycle-aware Worker source.
CREATE TABLE IF NOT EXISTS account_retirements (
  user_id TEXT PRIMARY KEY,
  retired_at TEXT NOT NULL DEFAULT (datetime('now')),
  clerk_deleted_at TEXT,
  clerk_identity_seen_at TEXT,
  clerk_binding_hash TEXT
);
