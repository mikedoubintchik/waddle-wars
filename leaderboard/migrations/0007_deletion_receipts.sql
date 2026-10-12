-- A deletion receipt is a status-only capability. Store only its SHA-256 digest,
-- never the client token, and do not choose a new retention/expiration period.
CREATE TABLE IF NOT EXISTS account_deletion_receipts (
  receipt_hash TEXT PRIMARY KEY NOT NULL
    CHECK (typeof(receipt_hash) = 'text' AND length(receipt_hash) = 64
      AND receipt_hash NOT GLOB '*[^0-9a-f]*'),
  user_id TEXT NOT NULL UNIQUE,
  FOREIGN KEY (user_id) REFERENCES account_retirements(user_id)
    DEFERRABLE INITIALLY DEFERRED
);

-- Receipt registration precedes the retirement marker in the same atomic batch.
-- A pre-existing retired subject cannot attach an arbitrary replacement token.
-- Check ownership before ON CONFLICT DO NOTHING: a collision must abort the
-- entire transaction, including any later retirement or personal-data erasure.
CREATE TRIGGER IF NOT EXISTS deletion_receipt_registration_guard
BEFORE INSERT ON account_deletion_receipts
WHEN EXISTS (SELECT 1 FROM account_deletion_receipts
  WHERE (receipt_hash = NEW.receipt_hash AND user_id <> NEW.user_id)
    OR (user_id = NEW.user_id AND receipt_hash <> NEW.receipt_hash))
  OR (EXISTS (SELECT 1 FROM account_retirements WHERE user_id = NEW.user_id)
    AND NOT EXISTS (SELECT 1 FROM account_deletion_receipts
      WHERE receipt_hash = NEW.receipt_hash AND user_id = NEW.user_id))
BEGIN SELECT RAISE(ABORT, 'deletion_receipt_conflict'); END;

CREATE TRIGGER IF NOT EXISTS deletion_receipt_ownership_immutable
BEFORE UPDATE ON account_deletion_receipts
WHEN NEW.receipt_hash <> OLD.receipt_hash OR NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'deletion_receipt_conflict'); END;
