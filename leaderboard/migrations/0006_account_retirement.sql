-- Account retirement is permanent and independent of reversible purchase refunds.
-- Retain the minimum subject marker needed to reject old JWTs and delayed writes.
CREATE TABLE IF NOT EXISTS account_retirements (
  user_id TEXT PRIMARY KEY,
  retired_at TEXT NOT NULL DEFAULT (datetime('now')),
  clerk_identity_seen_at TEXT,
  clerk_binding_hash TEXT,
  clerk_deleted_at TEXT
);

-- Request authentication alone cannot fence work already awaiting a provider.
-- These checks execute atomically with each attempted write in D1/SQLite.
CREATE TRIGGER IF NOT EXISTS retired_scores_insert
BEFORE INSERT ON scores
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_scores_update
BEFORE UPDATE ON scores
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_profiles_insert
BEFORE INSERT ON profiles
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_profiles_update
BEFORE UPDATE ON profiles
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_saves_insert
BEFORE INSERT ON saves
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_saves_update
BEFORE UPDATE ON saves
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_store_accounts_insert
BEFORE INSERT ON commerce_store_accounts
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_store_accounts_update
BEFORE UPDATE ON commerce_store_accounts
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

-- Anonymous pending PKCE requests are allowed. Approval cannot attach a retired
-- subject, including requests that were not identifiable during the deletion.
CREATE TRIGGER IF NOT EXISTS retired_native_auth_requests_insert
BEFORE INSERT ON commerce_native_auth_requests
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_native_auth_requests_update
BEFORE UPDATE ON commerce_native_auth_requests
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_native_auth_sessions_insert
BEFORE INSERT ON commerce_native_auth_sessions
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_native_auth_sessions_update
BEFORE UPDATE ON commerce_native_auth_sessions
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

-- Financial proof is retained pending lawful retention policy. Retirement
-- prevents new ownership and any reactivation, while allowing verified refunds
-- or disputes to update existing evidence for the same subject.
CREATE TRIGGER IF NOT EXISTS retired_checkouts_insert
BEFORE INSERT ON commerce_checkouts
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_checkouts_update
BEFORE UPDATE ON commerce_checkouts
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
  AND (NEW.state IN ('pending', 'paid') OR NEW.user_id <> OLD.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_purchases_insert
BEFORE INSERT ON commerce_purchases
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;

CREATE TRIGGER IF NOT EXISTS retired_purchases_update
BEFORE UPDATE ON commerce_purchases
WHEN EXISTS (SELECT 1 FROM account_retirements WHERE user_id IN (OLD.user_id, NEW.user_id))
  AND (NEW.state = 'active' OR NEW.user_id <> OLD.user_id)
BEGIN SELECT RAISE(ABORT, 'account_retired'); END;
