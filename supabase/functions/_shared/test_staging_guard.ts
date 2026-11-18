// TalkMate AI - Staging Environment Test Isolation Guard (SEC-E / Issue A & B)
// Strictly enforces that real integration tests only run against verified staging environments.
//
// Mandatory Rules:
// 1. Explicit opt-in: TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS="true"
// 2. Dedicated staging variables ONLY:
//    - TALKMATE_STAGING_SUPABASE_URL
//    - TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY
//    - TALKMATE_STAGING_SUPABASE_SECRET_KEY
//    - TALKMATE_STAGING_PROJECT_REF
// 3. Exact project hostname matching: ${TALKMATE_STAGING_PROJECT_REF.toLowerCase()}.supabase.co
// 4. Dedicated staging PostgreSQL variables ONLY:
//    - TALKMATE_STAGING_PGHOST
//    - TALKMATE_STAGING_PGPORT
//    - TALKMATE_STAGING_PGUSER
//    - TALKMATE_STAGING_PGPASSWORD
//    - TALKMATE_STAGING_PGDATABASE
// 5. Zero silent fallback to generic SUPABASE_* or PG* variables.
// 6. Zero credential exposure in errors or logs.

export interface StagingTestEnvironment {
  supabaseUrl: string;
  projectRef: string;
  publishableKey: string;
  secretKey: string;
}

export interface StagingPostgresEnvironment {
  host: string;
  port: number;
  user: string;
  pass: string;
  database: string;
  projectRef: string;
}

// Known production project reference to explicitly forbid
const FORBIDDEN_PRODUCTION_PROJECT_REF = 'icdbbfsjbslzctshxytd';

/**
 * Checks whether staging integration tests are explicitly allowed.
 */
export function canRunStagingTests(): boolean {
  return Deno.env.get('TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS') === 'true';
}

/**
 * Asserts that the staging environment is configured and verified, throwing an error if not.
 */
export function assertStagingEnvironment(
  suiteName?: string,
): StagingTestEnvironment {
  const env = getVerifiedStagingEnvironment();
  if (!env) {
    throw new Error(
      `Staging test suite '${
        suiteName || 'unspecified'
      }' attempted execution without TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS="true".`,
    );
  }
  return env;
}

/**
 * Validates and returns the HTTPS staging Supabase environment.
 * Returns null if TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS is not "true".
 * Throws strict descriptive errors (without exposing secrets) if configured improperly.
 */
export function getVerifiedStagingEnvironment(): StagingTestEnvironment | null {
  const allowStaging = Deno.env.get('TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS');
  if (allowStaging !== 'true') {
    return null;
  }

  // Strictly forbid silent fallback to generic SUPABASE_* variables
  const rawUrl = Deno.env.get('TALKMATE_STAGING_SUPABASE_URL');
  const rawProjectRef = Deno.env.get('TALKMATE_STAGING_PROJECT_REF');
  const rawPublishableKey = Deno.env.get(
    'TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY',
  );
  const rawSecretKey = Deno.env.get('TALKMATE_STAGING_SUPABASE_SECRET_KEY');

  if (!rawProjectRef || rawProjectRef.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PROJECT_REF is required when TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS=true.',
    );
  }

  const projectRef = rawProjectRef.trim().toLowerCase();

  // Validate project ref format
  if (!/^[a-z0-9_-]+$/i.test(projectRef)) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PROJECT_REF contains invalid characters.',
    );
  }

  // Refuse if someone passed the production project reference
  if (projectRef === FORBIDDEN_PRODUCTION_PROJECT_REF) {
    throw new Error(
      'Security violation: TALKMATE_STAGING_PROJECT_REF matches production project reference. Staging tests cannot target production.',
    );
  }

  if (!rawUrl || rawUrl.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_SUPABASE_URL is required when TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS=true. Generic SUPABASE_URL fallback is strictly forbidden.',
    );
  }

  if (!rawPublishableKey || rawPublishableKey.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY is required. Generic key fallbacks are strictly forbidden.',
    );
  }

  if (!rawSecretKey || rawSecretKey.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_SUPABASE_SECRET_KEY is required. Generic key fallbacks are strictly forbidden.',
    );
  }

  // Parse and validate URL
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(rawUrl.trim());
  } catch (_e) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_SUPABASE_URL is not a syntactically valid URL.',
    );
  }

  // Validate protocol
  if (parsedUrl.protocol.toLowerCase() !== 'https:') {
    throw new Error(
      `Security violation: TALKMATE_STAGING_SUPABASE_URL must use HTTPS protocol. Found '${parsedUrl.protocol}'.`,
    );
  }

  // Validate no URL credentials embedded
  if (parsedUrl.username || parsedUrl.password) {
    throw new Error(
      'Security violation: TALKMATE_STAGING_SUPABASE_URL must not contain embedded user credentials in URL.',
    );
  }

  // Validate port: only empty or 443 permitted for HTTPS Supabase
  if (parsedUrl.port !== '' && parsedUrl.port !== '443') {
    throw new Error(
      `Security violation: TALKMATE_STAGING_SUPABASE_URL contains unexpected port '${parsedUrl.port}'. Expected standard HTTPS port 443.`,
    );
  }

  // Validate no path segments, query parameters, or fragments
  if (parsedUrl.pathname !== '' && parsedUrl.pathname !== '/') {
    throw new Error(
      `Security violation: TALKMATE_STAGING_SUPABASE_URL must not contain path segments. Found '${parsedUrl.pathname}'.`,
    );
  }
  if (parsedUrl.search) {
    throw new Error(
      'Security violation: TALKMATE_STAGING_SUPABASE_URL must not contain query parameters.',
    );
  }
  if (parsedUrl.hash) {
    throw new Error(
      'Security violation: TALKMATE_STAGING_SUPABASE_URL must not contain URL fragments.',
    );
  }

  // Exact hostname validation: must match exactly `${projectRef}.supabase.co`
  const expectedHostname = `${projectRef}.supabase.co`;
  const actualHostname = parsedUrl.hostname.toLowerCase();

  if (actualHostname !== expectedHostname) {
    throw new Error(
      `Security violation: Supabase URL hostname '${actualHostname}' does not match expected staging hostname '${expectedHostname}'. Loose substring matching is strictly forbidden.`,
    );
  }

  return {
    supabaseUrl: parsedUrl.origin,
    projectRef,
    publishableKey: rawPublishableKey.trim(),
    secretKey: rawSecretKey.trim(),
  };
}

/**
 * Validates and returns dedicated PostgreSQL staging credentials.
 * Returns null if TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS is not "true".
 * Requires dedicated TALKMATE_STAGING_PG* variables and TALKMATE_STAGING_PROJECT_REF.
 * Strictly forbids fallback to generic PGHOST, PGUSER, PGPASSWORD, etc.
 */
export function getVerifiedStagingPostgresEnvironment():
  | StagingPostgresEnvironment
  | null {
  const allowStaging = Deno.env.get('TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS');
  if (allowStaging !== 'true') {
    return null;
  }

  const rawProjectRef = Deno.env.get('TALKMATE_STAGING_PROJECT_REF');
  if (!rawProjectRef || rawProjectRef.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PROJECT_REF is required for PostgreSQL staging tests.',
    );
  }
  const projectRef = rawProjectRef.trim().toLowerCase();

  if (projectRef === FORBIDDEN_PRODUCTION_PROJECT_REF) {
    throw new Error(
      'Security violation: TALKMATE_STAGING_PROJECT_REF matches production project reference. PostgreSQL tests cannot target production.',
    );
  }

  const host = Deno.env.get('TALKMATE_STAGING_PGHOST');
  const user = Deno.env.get('TALKMATE_STAGING_PGUSER');
  const pass = Deno.env.get('TALKMATE_STAGING_PGPASSWORD');
  const portStr = Deno.env.get('TALKMATE_STAGING_PGPORT') || '5432';
  const database = Deno.env.get('TALKMATE_STAGING_PGDATABASE') || 'postgres';

  if (!host || host.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PGHOST is required. Generic PGHOST fallback is forbidden.',
    );
  }

  if (!user || user.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PGUSER is required. Generic PGUSER fallback is forbidden.',
    );
  }

  if (!pass || pass.trim().length === 0) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PGPASSWORD is required. Generic PGPASSWORD fallback is forbidden.',
    );
  }

  const port = parseInt(portStr.trim(), 10);
  if (isNaN(port) || port <= 0 || port > 65535) {
    throw new Error(
      'Staging configuration error: TALKMATE_STAGING_PGPORT is invalid.',
    );
  }

  const trimmedHost = host.trim().toLowerCase();

  // Forbid production host
  if (trimmedHost.includes(FORBIDDEN_PRODUCTION_PROJECT_REF)) {
    throw new Error(
      'Security violation: TALKMATE_STAGING_PGHOST matches production project reference. PostgreSQL tests cannot target production.',
    );
  }

  // Validate that host belongs to expected Supabase staging domain
  const isDirectDb = trimmedHost === `db.${projectRef}.supabase.co`;
  const isPoolerHost = /^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$/.test(
    trimmedHost,
  );

  if (!isDirectDb && !isPoolerHost) {
    throw new Error(
      `Security violation: PostgreSQL host '${trimmedHost}' does not match expected staging host pattern for project '${projectRef}'.`,
    );
  }

  if (isDirectDb) {
    if (port !== 5432) {
      throw new Error(
        `Security violation: Direct PostgreSQL connection to '${trimmedHost}' must use port 5432. Found '${port}'.`,
      );
    }
    if (user.toLowerCase().includes(FORBIDDEN_PRODUCTION_PROJECT_REF)) {
      throw new Error(
        'Security violation: PostgreSQL user matches production project reference. PostgreSQL tests cannot target production.',
      );
    }
  } else if (isPoolerHost) {
    if (port !== 5432 && port !== 6543) {
      throw new Error(
        `Security violation: PostgreSQL pooler connection to '${trimmedHost}' must use port 5432 or 6543. Found '${port}'.`,
      );
    }
    const trimmedUser = user.trim().toLowerCase();
    if (trimmedUser.includes(FORBIDDEN_PRODUCTION_PROJECT_REF)) {
      throw new Error(
        'Security violation: PostgreSQL pooler user matches production project reference. PostgreSQL tests cannot target production.',
      );
    }
    // Strict pooler username grammar: <db_user>.<projectRef>
    // db_user must be a valid PostgreSQL identifier (letters, digits, underscores)
    // projectRef must match exactly after the single separating dot.
    const escapedProjectRef = projectRef.replace(
      /[-/\\^$*+?.()|[\]{}]/g,
      '\\$&',
    );
    const poolerUserPattern = new RegExp(
      `^[a-z0-9_]+\\.${escapedProjectRef}$`,
      'i',
    );
    const isPoolerUserForProject = poolerUserPattern.test(trimmedUser);
    if (!isPoolerUserForProject) {
      throw new Error(
        `Security violation: PostgreSQL pooler username '${user}' does not belong to staging project '${projectRef}'. Expected user format '<db_user>.${projectRef}'.`,
      );
    }
  }

  return {
    host: trimmedHost,
    port,
    user: user.trim(),
    pass: pass.trim(),
    database: database.trim(),
    projectRef,
  };
}
