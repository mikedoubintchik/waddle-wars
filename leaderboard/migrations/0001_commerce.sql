-- Apply to the existing D1 database with its normal migration workflow.
-- Purchase ownership never comes from the user-editable cloud save.
CREATE TABLE IF NOT EXISTS commerce_checkouts (
  request_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  stripe_session_id TEXT UNIQUE,
  payment_intent_id TEXT UNIQUE,
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'paid', 'refunded', 'disputed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS commerce_checkouts_user ON commerce_checkouts(user_id, state);

CREATE TABLE IF NOT EXISTS commerce_purchases (
  provider TEXT NOT NULL CHECK (provider IN ('stripe', 'apple', 'google')),
  transaction_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  payment_reference TEXT,
  state TEXT NOT NULL CHECK (state IN ('active', 'refunded', 'disputed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (provider, transaction_id)
);
CREATE INDEX IF NOT EXISTS commerce_purchases_user ON commerce_purchases(user_id, state);
CREATE INDEX IF NOT EXISTS commerce_purchases_payment ON commerce_purchases(provider, payment_reference);

CREATE TABLE IF NOT EXISTS commerce_events (
  provider TEXT NOT NULL,
  event_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (provider, event_id)
);
