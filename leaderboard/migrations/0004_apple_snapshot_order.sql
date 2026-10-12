-- Apple's certificate-verified JWS signedDate orders authoritative snapshots.
-- A delayed refund/reversal response must not override a newer provider state.
ALTER TABLE commerce_purchases ADD COLUMN provider_signed_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE commerce_revocations ADD COLUMN provider_signed_at INTEGER NOT NULL DEFAULT 0;
