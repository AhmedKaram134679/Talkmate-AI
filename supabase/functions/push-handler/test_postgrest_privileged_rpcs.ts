// TalkMate AI - Privileged RPC HTTPS PostgREST Integration Test Suite (SEC-03 / SEC-07)
// Verifies real HTTPS requests to PostgREST with STRICT TLS certificate validation.
// Run with: deno test --no-config --allow-net supabase/functions/push-handler/test_postgrest_privileged_rpcs.ts

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const SUPABASE_URL = "https://icdbbfsjbslzctshxytd.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0Mjg2NjgsImV4cCI6MjA5NjAwNDY2OH0.RXHSRZeTalHY3shnFuoHrkaS2gYT4XqgJzgfmkUschw";
const SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDQyODY2OCwiZXhwIjoyMDk2MDA0NjY4fQ.VmBetxbbIBDF9gxnAKC_cikCXLD66jXao-YR9I_Tm0Y";

Deno.test("SEC-03 / SEC-07: Unauthenticated request to purge_old_data is denied (401)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": ANON_KEY,
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
      "apikey": ANON_KEY,
      "Authorization": `Bearer ${ANON_KEY}`,
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
      "apikey": SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
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
        "apikey": ANON_KEY,
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
        "apikey": ANON_KEY,
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
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      },
    });
    await delRes.text();
  }
});

Deno.test("SEC-03: Service role invocation with valid retention_days succeeds (204)", async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_old_data`, {
    method: "POST",
    headers: {
      "apikey": SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
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
      "apikey": SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
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
      "apikey": SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ retention_days: 5000 }),
  });

  assertEquals(res.status, 400, "Service role call with retention 5000 must return 400 Bad Request");
  const data = await res.json();
  assertEquals(data.code, "22023");
  assert(data.message.includes("Invalid retention period"));
});
