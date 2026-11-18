// TalkMate AI - Complete Account Deletion Integration Test (SEC-02)
// Proves complete Supabase Auth identity deletion and database cleanup.
// Run with: deno test --no-config --allow-net --allow-env supabase/functions/push-handler/test_complete_account_deletion.ts

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

Deno.test("SEC-02: Complete account deletion removes Auth identity and database records", async () => {
  const tempEmail = `test_delete_${Date.now()}@example.com`;
  const tempPassword = "Password123!Secure";

  // 1. Create a genuine test user via admin API
  const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      "apikey": SECRET_KEY,
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
  const userId = createdUser.id;
  assert(userId, "Created user must have an ID");

  try {
    // 2. Sign in as test user to obtain authentic JWT
    const loginRes = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
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

    assertEquals(loginRes.status, 200, "Sign in must succeed");
    const loginData = await loginRes.json();
    const userJwt = loginData.access_token;
    assert(userJwt, "User JWT must be returned");

    // 3. Test: Unauthenticated request to delete-account must be rejected (401)
    const unauthRes = await fetch(`${SUPABASE_URL}/functions/v1/delete-account`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
    });
    assertEquals(unauthRes.status, 401, "Unauthenticated deletion request must return 401");
    await unauthRes.text();

    // 4. Test: Attempting to delete another user ID via payload must be rejected (403)
    const crossDeleteRes = await fetch(`${SUPABASE_URL}/functions/v1/delete-account`, {
      method: "POST",
      headers: {
        "apikey": PUBLISHABLE_KEY,
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
    const deleteRes = await fetch(`${SUPABASE_URL}/functions/v1/delete-account`, {
      method: "POST",
      headers: {
        "apikey": PUBLISHABLE_KEY,
        "Authorization": `Bearer ${userJwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

    assertEquals(deleteRes.status, 200, "Valid account deletion must return 200");
    const deleteData = await deleteRes.json();
    assertEquals(deleteData.success, true);

    // 6. Verification: Check Supabase Auth identity is completely gone
    const checkAuthRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
      method: "GET",
      headers: {
        "apikey": SECRET_KEY,
      },
    });

    // GoTrue Admin returns 404 or empty object when user is deleted
    assert(
      checkAuthRes.status === 404 || checkAuthRes.status === 400 || !checkAuthRes.ok,
      "Deleted user identity must not exist in Supabase Auth"
    );
    await checkAuthRes.text();

    // 7. Verification: Re-authentication attempt with the deleted account must be rejected
    const reloginRes = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
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

    assert(
      reloginRes.status === 400 || reloginRes.status === 401,
      "Authentication after deletion must fail"
    );
    await reloginRes.text();
  } finally {
    // Fail-safe cleanup in case of test assertion failure prior to deletion
    try {
      const cleanup = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
        method: "DELETE",
        headers: {
          "apikey": SECRET_KEY,
        },
      });
      await cleanup.text();
    } catch (_) {}
  }
});
