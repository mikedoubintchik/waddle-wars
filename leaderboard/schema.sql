-- One row per (user, mode, course); value is ms for mode='time' (lower is
-- better) and meters for mode='endless' (higher is better).
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
