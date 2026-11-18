// TalkMate AI - Privileged RPC HTTPS PostgREST Integration Test Suite (SEC-03 / SEC-07)
// Verifies real HTTPS requests to PostgREST against verified Staging environment.
// Run with: deno test --allow-net --allow-env supabase/functions/push-handler/test_postgrest_privileged_rpcs.ts

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getVerifiedStagingEnvironment } from "../_shared/test_staging_guard.ts";

const stagingEnv = getVerifiedStagingEnvironment();

Deno.test({
  name: "SEC-03 / SEC-07: Unauthenticated request to purge_old_data is denied (401)",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const res = await fetch(`${env.supabaseUrl}/rest/v1/rpc/purge_old_data`, {
      method: "POST",
      headers: {
        "apikey": env.publishableKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ retention_days: 90 }),
    });

    assertEquals(res.status, 401);
    const data = await res.json();
    assertEquals(data.code, "42501");
    assert(data.message.includes("permission denied for function purge_old_data"));
  },
});

Deno.test({
  name: "SEC-03 / SEC-07: Malformed or non-JWT Bearer token to purge_old_data is denied (401)",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const res = await fetch(`${env.supabaseUrl}/rest/v1/rpc/purge_old_data`, {
      method: "POST",
      headers: {
        "apikey": env.publishableKey,
        "Authorization": `Bearer ${env.publishableKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ retention_days: 90 }),
    });

    assertEquals(res.status, 401);
    const data = await res.json();
    assertEquals(data.code, "42501");
    assert(data.message.includes("permission denied for function purge_old_data"));
  },
});

Deno.test({
  name: "SEC-03 / SEC-07: Authenticated user JWT to purge_old_data is denied (401 or 403)",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const tempEmail = `test_audit_${Date.now()}_${Math.random().toString(36).substring(7)}@example.com`;
    const tempPassword = "TempPassword_987654!";
    let userId: string | null = null;

    try {
      // 1. Create a real user using admin API
      const createRes = await fetch(`${env.supabaseUrl}/auth/v1/admin/users`, {
        method: "POST",
        headers: {
          "apikey": env.secretKey,
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
      userId = createdUser.id;

      // 2. Sign in to obtain genuine user access token (role: authenticated)
      const tokenRes = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
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
      const res = await fetch(`${env.supabaseUrl}/rest/v1/rpc/purge_old_data`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${userJwt}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ retention_days: 90 }),
      });

      // PostgREST returns 401 or 403 Forbidden for authenticated users without permission
      assert(
        res.status === 401 || res.status === 403,
        "Authenticated client must NOT be allowed to invoke purge_old_data"
      );
      const data = await res.json();
      assertEquals(data.code, "42501");
      assert(data.message.includes("permission denied for function purge_old_data"));
    } finally {
      if (userId) {
        try {
          const delRes = await fetch(`${env.supabaseUrl}/auth/v1/admin/users/${userId}`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
            },
          });
          await delRes.text();
        } catch (_) {}
      }
    }
  },
});

Deno.test({
  name: "SEC-03: Service role invocation with valid retention_days succeeds (204)",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const res = await fetch(`${env.supabaseUrl}/rest/v1/rpc/purge_old_data`, {
      method: "POST",
      headers: {
        "apikey": env.secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ retention_days: 90 }),
    });

    assertEquals(res.status, 204, "Service role call with valid retention must return 204 No Content");
    await res.text();
  },
});

Deno.test({
  name: "SEC-03: Service role invocation with invalid retention_days (< 1) is rejected (400)",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const res = await fetch(`${env.supabaseUrl}/rest/v1/rpc/purge_old_data`, {
      method: "POST",
      headers: {
        "apikey": env.secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ retention_days: 0 }),
    });

    assertEquals(res.status, 400, "Service role call with retention 0 must return 400 Bad Request");
    const data = await res.json();
    assertEquals(data.code, "22023");
    assert(data.message.includes("Invalid retention period"));
  },
});

Deno.test({
  name: "SEC-03: Service role invocation with invalid retention_days (> 3650) is rejected (400)",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const res = await fetch(`${env.supabaseUrl}/rest/v1/rpc/purge_old_data`, {
      method: "POST",
      headers: {
        "apikey": env.secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ retention_days: 5000 }),
    });

    assertEquals(res.status, 400, "Service role call with retention 5000 must return 400 Bad Request");
    const data = await res.json();
    assertEquals(data.code, "22023");
    assert(data.message.includes("Invalid retention period"));
  },
});
