// TalkMate AI - Privileged RPC HTTPS PostgREST Integration Test Suite (SEC-03 / SEC-07)
// Verifies real HTTPS requests to PostgREST with STRICT TLS certificate validation.
// Run with: deno test --no-config --allow-net --allow-env supabase/functions/push-handler/test_postgrest_privileged_rpcs.ts

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://icdbbfsjbslzctshxytd.supabase.co";

function getPublishableKey(): string {
  const directKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (directKey && directKey.trim().length > 0) return directKey.trim();
  const dictRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
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

function getSecretKey(): string {
  const directKey = Deno.env.get("SUPABASE_SECRET_KEY");
  if (directKey && directKey.trim().length > 0) return directKey.trim();
  const dictRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
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

const PUBLISHABLE_KEY = getPublishableKey();
const SECRET_KEY = getSecretKey();

if (!PUBLISHABLE_KEY || !SECRET_KEY) {
  throw new Error(
    "Security requirement violation: SUPABASE_PUBLISHABLE_KEY (or SUPABASE_PUBLISHABLE_KEYS) and SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEYS) must be provided via environment variables. Legacy keys are rejected."
  );
}

Deno.test("SEC-03 / SEC-07: Unauthenticated request to purge_old_data is denied (401)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": PUBLISHABLE_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ retention_days: 90 }),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assertEquals(data.code, "42501");
  assert(data.message.includes("permission denied for function purge_old_data"));
});

Deno.test("SEC-03 / SEC-07: Anon role JWT request to purge_old_data is denied (401)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": PUBLISHABLE_KEY,
      "Authorization": `Bearer ${PUBLISHABLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ retention_days: 90 }),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assertEquals(data.code, "42501");
  assert(data.message.includes("permission denied for function purge_old_data"));
});

Deno.test("SEC-03 / SEC-07: Authenticated user JWT to purge_old_data is denied (401)", async () => {
  const tempEmail = `test_audit_${Date.now()}@example.com`;
  const tempPassword = "TempPassword_987654!";

  // 1. Create a real user using admin API
  const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      "apikey": SECRET_KEY,
      "Authorization": `Bearer ${SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email: tempEmail,
      password: tempPassword,
      email_confirm: true,
    }),
  });

  assertEquals(createRes.status, 200, "Failed to create test user");
  const createdUser = await createRes.json();
  const userId = createdUser.id;

  try {
    // 2. Sign in to obtain genuine user access token (role: authenticated)
    const tokenRes = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: {
        "apikey": PUBLISHABLE_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: tempEmail,
        password: tempPassword,
      }),
    });
    assertEquals(tokenRes.status, 200, "Failed to sign in as test user");
    const tokenData = await tokenRes.json();
    const userJwt = tokenData.access_token;
    assert(userJwt, "Missing user access token");

    // 3. Attempt to invoke purge_old_data as authenticated user
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
      method: "POST",
      headers: {
        "apikey": PUBLISHABLE_KEY,
        "Authorization": `Bearer ${userJwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ retention_days: 90 }),
    });

    // PostgREST returns 403 Forbidden for authenticated users without permission
    assert(res.status === 401 || res.status === 403, "Authenticated client must NOT be allowed to invoke purge_old_data");
    const data = await res.json();
    assertEquals(data.code, "42501");
    assert(data.message.includes("permission denied for function purge_old_data"));
  } finally {
    // Cleanup user
    const delRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
      method: "DELETE",
      headers: {
        "apikey": SECRET_KEY,
        "Authorization": `Bearer ${SECRET_KEY}`,
      },
    });
    await delRes.text();
  }
});

Deno.test("SEC-03: Service role invocation with valid retention_days succeeds (204)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": SECRET_KEY,
      "Authorization": `Bearer ${SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ retention_days: 90 }),
  });

  assertEquals(res.status, 204, "Service role call with valid retention must return 204 No Content");
  await res.text();
});

Deno.test("SEC-03: Service role invocation with invalid retention_days (< 1) is rejected (400)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": SECRET_KEY,
      "Authorization": `Bearer ${SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ retention_days: 0 }),
  });

  assertEquals(res.status, 400, "Service role call with retention 0 must return 400 Bad Request");
  const data = await res.json();
  assertEquals(data.code, "22023");
  assert(data.message.includes("Invalid retention period"));
});

Deno.test("SEC-03: Service role invocation with invalid retention_days (> 3650) is rejected (400)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": SECRET_KEY,
      "Authorization": `Bearer ${SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ retention_days: 5000 }),
  });

  assertEquals(res.status, 400, "Service role call with retention 5000 must return 400 Bad Request");
  const data = await res.json();
  assertEquals(data.code, "22023");
  assert(data.message.includes("Invalid retention period"));
});
