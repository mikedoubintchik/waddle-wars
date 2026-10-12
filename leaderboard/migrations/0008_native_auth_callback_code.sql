-- Native iOS v2 requires a one-use callback code as well as the private PKCE
-- verifier. A requester polling a shared sign-in URL cannot receive a token.
ALTER TABLE commerce_native_auth_requests ADD COLUMN flow_version INTEGER NOT NULL DEFAULT 1 CHECK (flow_version IN (1, 2));
ALTER TABLE commerce_native_auth_requests ADD COLUMN callback_code_hash TEXT;
ALTER TABLE commerce_native_auth_requests ADD COLUMN callback_code_expires_at INTEGER;
ALTER TABLE commerce_native_auth_requests ADD COLUMN callback_code_consumed_at INTEGER;
