// TalkMate AI - Staging Environment Test Isolation Guard (SEC-E)
// Strictly enforces that real integration tests only run when:
// 1. Explicit opt-in: TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS="true"
// 2. Explicit Staging project reference: TALKMATE_STAGING_PROJECT_REF is set
// 3. Explicit Staging Supabase URL: TALKMATE_STAGING_SUPABASE_URL (or SUPABASE_URL) matches project reference
// 4. Genuine Publishable and Secret API keys are provided
// 5. Zero silent fallback to production.

export interface StagingTestEnvironment {
  supabaseUrl: string;
  projectRef: string;
  publishableKey: string;
  secretKey: string;
}

export function parseKeyFromEnv(directVar: string, dictVar: string): string {
  const directKey = Deno.env.get(directVar);
  if (directKey && directKey.trim().length > 0) return directKey.trim();
  const dictRaw = Deno.env.get(dictVar);
  if (dictRaw && dictRaw.trim().length > 0) {
    try {
      const parsed = JSON.parse(dictRaw);
      if (parsed?.default && typeof parsed.default === "string" && parsed.default.trim().length > 0) {
        return parsed.default.trim();
      }
    } catch (_) {}
  }
  return "";
}

export function getVerifiedStagingEnvironment(): StagingTestEnvironment | null {
  const allowStaging = Deno.env.get("TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS");
  if (allowStaging !== "true") {
    return null;
  }

  const supabaseUrl = Deno.env.get("TALKMATE_STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
  const projectRef = Deno.env.get("TALKMATE_STAGING_PROJECT_REF");

  if (!supabaseUrl || !projectRef) {
    throw new Error(
      "Staging configuration error: Both TALKMATE_STAGING_SUPABASE_URL (or SUPABASE_URL) and TALKMATE_STAGING_PROJECT_REF must be explicitly provided when TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS=true."
    );
  }

  // Refuse if project reference does not match URL
  if (!supabaseUrl.includes(projectRef)) {
    throw new Error(
      `Security violation: Configured project reference '${projectRef}' does not match Supabase URL '${supabaseUrl}'. Integration tests aborted.`
    );
  }

  const publishableKey = parseKeyFromEnv("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_PUBLISHABLE_KEYS");
  const secretKey = parseKeyFromEnv("SUPABASE_SECRET_KEY", "SUPABASE_SECRET_KEYS");

  if (!publishableKey || !secretKey) {
    throw new Error(
      "Staging configuration error: Both Publishable and Secret API keys must be provided."
    );
  }

  return {
    supabaseUrl: supabaseUrl.trim().replace(/\/$/, ""),
    projectRef: projectRef.trim(),
    publishableKey,
    secretKey,
  };
}
