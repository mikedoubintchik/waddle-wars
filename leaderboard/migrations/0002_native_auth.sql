-- Native PKCE handoff is separate from cosmetic ownership. Only a verified
-- Clerk web session can approve a request; device verifier stays off URLs.
CREATE TABLE IF NOT EXISTS commerce_native_auth_requests (
  request_id TEXT PRIMARY KEY,
  challenge TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'approved', 'exchanged', 'cancelled')),
  user_id TEXT,
  clerk_session_id TEXT,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS commerce_native_auth_sessions (
  request_id TEXT PRIMARY KEY,
  verifier_hash TEXT NOT NULL,
  user_id TEXT NOT NULL,
  clerk_session_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0 CHECK (revoked IN (0, 1))
);
