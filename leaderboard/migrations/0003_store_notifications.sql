CREATE TABLE IF NOT EXISTS commerce_store_accounts (
  user_id TEXT PRIMARY KEY,
  apple_account_token TEXT NOT NULL UNIQUE,
  google_account_id TEXT NOT NULL UNIQUE
);
-- Verified provider revocations can precede client fulfillment. A tombstone
-- prevents a stale purchased response from granting a refunded transaction.
CREATE TABLE IF NOT EXISTS commerce_revocations (
  provider TEXT NOT NULL CHECK (provider IN ('apple', 'google')),
  transaction_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (provider, transaction_id)
);
