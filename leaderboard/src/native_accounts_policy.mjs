// Explicit second issuer for the native release. Existing web accounts keep
// their original issuer; JWT claims can never choose an arbitrary JWKS host.
export const NATIVE_CLERK_ISSUER = 'https://clerk.waddlewars.io';
export const NATIVE_CLERK_PUBLISHABLE_KEY = 'pk_live_Y2xlcmsud2FkZGxld2Fycy5pbyQ';
export const NATIVE_AUTH_ORIGIN = 'https://waddlewars.io';
export const NATIVE_SUBJECT_PREFIX = 'clerk_live:';

export function nativeStorageSubject(subject) {
  if (typeof subject !== 'string' || !/^[A-Za-z0-9_-]{1,256}$/.test(subject)) throw new Error('invalid native subject');
  return NATIVE_SUBJECT_PREFIX + subject;
}

export function providerSubject(env, subject) {
  if (env.ACCOUNT_SUBJECT_PREFIX !== NATIVE_SUBJECT_PREFIX) return subject;
  if (typeof subject !== 'string' || !subject.startsWith(NATIVE_SUBJECT_PREFIX)) throw new Error('invalid native subject');
  const raw = subject.slice(NATIVE_SUBJECT_PREFIX.length);
  if (nativeStorageSubject(raw) !== subject) throw new Error('invalid native subject');
  return raw;
}

export function acceptedClerkIssuer(env, claimedIssuer) {
  if (typeof claimedIssuer !== 'string') return null;
  if (claimedIssuer === env.CLERK_ISSUER) return claimedIssuer;
  if (env.NATIVE_ACCOUNTS_ENABLED === 'true' && env.NATIVE_CLERK_ISSUER === NATIVE_CLERK_ISSUER &&
      claimedIssuer === NATIVE_CLERK_ISSUER) return claimedIssuer;
  return null;
}

export function nativeAccountEnvironment(env) {
  // The key remains an encrypted Worker secret. Never reuse the development
  // Clerk key or allow a deployment typo to switch native accounts to testing.
  if (env.NATIVE_ACCOUNTS_ENABLED !== 'true' || env.NATIVE_CLERK_ISSUER !== NATIVE_CLERK_ISSUER ||
      typeof env.NATIVE_CLERK_SECRET_KEY !== 'string' || !env.NATIVE_CLERK_SECRET_KEY.startsWith('sk_live_')) return null;
  return { ...env, CLERK_ISSUER: NATIVE_CLERK_ISSUER, CLERK_SECRET_KEY: env.NATIVE_CLERK_SECRET_KEY,
    NATIVE_ACCOUNTS_ENABLED: 'false', ACCOUNT_SUBJECT_PREFIX: NATIVE_SUBJECT_PREFIX, COMMERCE_NATIVE_AUTH_ENABLED: 'true',
    COMMERCE_NATIVE_AUTH_ORIGIN: NATIVE_AUTH_ORIGIN, COMMERCE_ALLOWED_ORIGINS: NATIVE_AUTH_ORIGIN,
    COMMERCE_CLERK_PUBLISHABLE_KEY: NATIVE_CLERK_PUBLISHABLE_KEY, ACCOUNT_DELETION_ENABLED: 'true' };
}
