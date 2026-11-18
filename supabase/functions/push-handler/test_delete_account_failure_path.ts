// TalkMate AI - Account Deletion Security & Fail-Closed Verification Tests
// Proves SEC-02: Fail-closed semantics, no partial deletions, identity boundary enforcement.

import { assertEquals, assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleDeleteAccount } from "../delete-account/index.ts";

const MOCK_CONFIG = {
  supabaseUrl: "https://mock.supabase.co",
  publishableKey: "sb_publishable_mock_test_key_12345",
  secretKey: "sb_secret_mock_test_key_67890",
};

Deno.test("SEC-02: Missing or non-Bearer authorization header returns 401", async () => {
  // Missing Authorization header
  const req1 = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
  });
  const res1 = await handleDeleteAccount(req1, MOCK_CONFIG);
  assertEquals(res1.status, 401);
  const data1 = await res1.json();
  assert(data1.error.includes("Missing or malformed authorization header"));

  // Malformed Authorization header (Basic instead of Bearer)
  const req2 = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Basic dXNlcjpwYXNz",
      "Content-Type": "application/json",
    },
  });
  const res2 = await handleDeleteAccount(req2, MOCK_CONFIG);
  assertEquals(res2.status, 401);
});

Deno.test("SEC-02: Invalid or expired session JWT returns 401", async () => {
  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: "Invalid token", status: 401 },
      }),
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer invalid_expired_jwt_token",
      "Content-Type": "application/json",
    },
  });

  const res = await handleDeleteAccount(req, {
    ...MOCK_CONFIG,
    userClient: mockUserClient,
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(data.error.includes("Invalid or expired session"));
});

Deno.test("SEC-02: Cross-user deletion attempt (targetUserId mismatch) returns 403 Forbidden", async () => {
  const authenticUserId = "11111111-1111-1111-1111-111111111111";
  const victimUserId = "22222222-2222-2222-2222-222222222222";

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: authenticUserId, email: "attacker@test.com" } },
        error: null,
      }),
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer valid_user_jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      targetUserId: victimUserId,
    }),
  });

  const res = await handleDeleteAccount(req, {
    ...MOCK_CONFIG,
    userClient: mockUserClient,
  });

  assertEquals(res.status, 403);
  const data = await res.json();
  assert(data.error.includes("Forbidden: You cannot delete an account that does not belong to you"));
});

Deno.test("SEC-02: RPC failure fails closed (500) and NEVER calls auth.admin.deleteUser", async () => {
  const userId = "33333333-3333-3333-3333-333333333333";
  let authDeleteCalled = false;

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async (fnName: string) => {
      assertEquals(fnName, "delete_user_account");
      return {
        data: null,
        error: { code: "40001", message: "Serialization failure or deadlock during deletion" },
      };
    },
  };

  const mockAdminClient = {
    storage: {
      from: () => ({
        list: async () => ({ data: [], error: null }),
        remove: async () => ({ data: [], error: null }),
      }),
    },
    auth: {
      admin: {
        deleteUser: async (_id: string) => {
          authDeleteCalled = true;
          return { data: { user: null }, error: null };
        },
      },
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer valid_user_jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });

  const res = await handleDeleteAccount(req, {
    ...MOCK_CONFIG,
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 500);
  const data = await res.json();
  assert(data.error.includes("Failed to clean up user database records. Account deletion aborted."));
  assertEquals(authDeleteCalled, false, "CRITICAL: auth.admin.deleteUser must NEVER be called when database RPC fails");
});

Deno.test("SEC-02: Full deletion path succeeds when RPC and Auth deletion succeed", async () => {
  const userId = "44444444-4444-4444-4444-444444444444";
  let rpcCalled = false;
  let authDeleteCalledWith = "";

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async (fnName: string) => {
      if (fnName === "delete_user_account") {
        rpcCalled = true;
        return { data: null, error: null };
      }
      return { data: null, error: { message: "Unknown function" } };
    },
  };

  const mockAdminClient = {
    storage: {
      from: (_bucket: string) => ({
        list: async (_prefix: string) => ({
          data: [{ name: "avatar.jpg" }],
          error: null,
        }),
        remove: async (paths: string[]) => {
          assertEquals(paths, [`users/${userId}/avatar.jpg`]);
          return { data: [], error: null };
        },
      }),
    },
    auth: {
      admin: {
        deleteUser: async (id: string) => {
          authDeleteCalledWith = id;
          return { data: { user: null }, error: null };
        },
      },
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer valid_user_jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });

  const res = await handleDeleteAccount(req, {
    ...MOCK_CONFIG,
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 200);
  const data = await res.json();
  assertEquals(data.success, true);
  assertEquals(rpcCalled, true, "RPC delete_user_account must have been called");
  assertEquals(authDeleteCalledWith, userId, "Auth deleteUser must have been called with user ID");
});

Deno.test("SEC-02: Non-POST HTTP methods return 405 Method Not Allowed", async () => {
  for (const method of ["GET", "PUT", "DELETE", "PATCH"]) {
    const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
      method,
      headers: { "Content-Type": "application/json" },
    });
    const res = await handleDeleteAccount(req, MOCK_CONFIG);
    assertEquals(res.status, 405);
  }
});
