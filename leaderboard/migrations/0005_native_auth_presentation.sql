-- Presentation is bound at request creation, not supplied by a later callback.
ALTER TABLE commerce_native_auth_requests ADD COLUMN presentation TEXT NOT NULL DEFAULT 'browser'
  CHECK (presentation IN ('browser', 'ios'));
