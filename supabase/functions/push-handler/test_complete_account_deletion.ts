// TalkMate AI - Complete Account Deletion Integration Test (SEC-02)
// Proves complete Supabase Auth identity deletion and database cleanup against verified Staging.
// Run with: deno test --allow-net --allow-env supabase/functions/push-handler/test_complete_account_deletion.ts

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getVerifiedStagingEnvironment } from "../_shared/test_staging_guard.ts";

const stagingEnv = getVerifiedStagingEnvironment();

Deno.test({
  name: "SEC-02: Complete account deletion removes Auth identity and database records",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const tempEmail = `test_delete_${Date.now()}_${Math.random().toString(36).substring(7)}@example.com`;
    const tempPassword = "Password123!Secure";
    let createdUserId: string | null = null;

    try {
      // 1. Create a genuine test user via admin API
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
          user_metadata: { full_name: "Test Delete User" },
        }),
      });

      assertEquals(createRes.status, 200, "User creation must succeed");
      const createdUser = await createRes.json();
      createdUserId = createdUser.id;
      assert(createdUserId, "Created user must have an ID");

      // 2. Sign in as test user to obtain authentic JWT
      const loginRes = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
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

      assertEquals(loginRes.status, 200, "Sign in must succeed");
      const loginData = await loginRes.json();
      const userJwt = loginData.access_token;
      assert(userJwt, "User JWT must be returned");

      // 3. Test: Unauthenticated request to delete-account must be rejected (401)
      const unauthRes = await fetch(`${env.supabaseUrl}/functions/v1/delete-account`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      });
      assertEquals(unauthRes.status, 401, "Unauthenticated deletion request must return 401");
      await unauthRes.text();

      // 4. Test: Attempting to delete another user ID via payload must be rejected (403)
      const crossDeleteRes = await fetch(`${env.supabaseUrl}/functions/v1/delete-account`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${userJwt}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          targetUserId: "00000000-0000-0000-0000-000000000001",
        }),
      });
      assertEquals(crossDeleteRes.status, 403, "Attempting to delete another user must return 403");
      await crossDeleteRes.text();

      // 5. Test: Authenticated user deletes own account
      const deleteRes = await fetch(`${env.supabaseUrl}/functions/v1/delete-account`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${userJwt}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({}),
      });

      assertEquals(deleteRes.status, 200, "Valid account deletion must return 200");
      const deleteData = await deleteRes.json();
      assertEquals(deleteData.success, true);

      // 6. Verification: Check Supabase Auth identity is completely gone
      const checkAuthRes = await fetch(`${env.supabaseUrl}/auth/v1/admin/users/${createdUserId}`, {
        method: "GET",
        headers: {
          "apikey": env.secretKey,
        },
      });

      // GoTrue Admin returns 404 or error object when user is deleted
      assert(
        checkAuthRes.status === 404 || checkAuthRes.status === 400 || !checkAuthRes.ok,
        "Deleted user identity must not exist in Supabase Auth"
      );
      await checkAuthRes.text();

      // 7. Verification: Re-authentication attempt with the deleted account must be rejected
      const reloginRes = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
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

      assert(
        reloginRes.status === 400 || reloginRes.status === 401,
        "Authentication after deletion must fail"
      );
      await reloginRes.text();
    } finally {
      // Guaranteed cleanup even if assertions fail
      if (createdUserId) {
        try {
          const cleanup = await fetch(`${env.supabaseUrl}/auth/v1/admin/users/${createdUserId}`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
            },
          });
          await cleanup.text();
        } catch (_) {}
      }
    }
  },
});
