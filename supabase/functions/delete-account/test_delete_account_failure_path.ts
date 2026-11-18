// TalkMate AI - Complete Account Deletion Security & Fail-Closed Unit Test Suite
// Verifies Section 5 & 6 requirements:
// - Deterministic fail-closed database RPC handling
// - Paginated and recursive Storage discovery and removal
// - Zero partial deletions: Auth identity is NEVER deleted if DB or Storage fails
// - Idempotent recovery on Auth 'not found'
// - Mutual exclusivity of user and admin roles

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleDeleteAccount, listAllStorageFiles } from "./index.ts";

const MOCK_CONFIG = {
  supabaseUrl: "https://mock.supabase.co",
  publishableKey: "mock_publishable_test_key_12345",
  secretKey: "mock_secret_test_key_67890",
};

// ============================================================================
// 1. DATABASE FAILURE & AUTHORIZATION TESTS
// ============================================================================

Deno.test("DB Failure: Missing or non-Bearer authorization header returns 401", async () => {
  const req1 = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
  });
  const res1 = await handleDeleteAccount(req1, MOCK_CONFIG);
  assertEquals(res1.status, 401);
  const data1 = await res1.json();
  assert(data1.error.includes("Missing or malformed authorization header"));

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

Deno.test("DB Failure: Invalid or expired session JWT returns 401", async () => {
  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: "Invalid or expired JWT token", status: 401 },
      }),
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer expired_user_jwt",
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

Deno.test("DB Failure: Cross-user deletion attempt (targetUserId mismatch) returns 403 Forbidden", async () => {
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
    body: JSON.stringify({ targetUserId: victimUserId }),
  });

  const res = await handleDeleteAccount(req, {
    ...MOCK_CONFIG,
    userClient: mockUserClient,
  });

  assertEquals(res.status, 403);
  const data = await res.json();
  assert(data.error.includes("Forbidden: You cannot delete an account that does not belong to you"));
});

Deno.test("DB Failure: RPC delete_user_account failure fails closed (500) and NEVER calls auth.admin.deleteUser", async () => {
  const userId = "33333333-3333-3333-3333-333333333333";
  let authDeleteCalled = false;
  let storageListCalled = false;

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
        error: { code: "40001", message: "Serialization deadlock during deletion" },
      };
    },
  };

  const mockAdminClient = {
    storage: {
      from: () => ({
        list: async () => {
          storageListCalled = true;
          return { data: [], error: null };
        },
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
  assertEquals(storageListCalled, false, "CRITICAL: Storage list must NEVER be called when DB RPC fails");
  assertEquals(authDeleteCalled, false, "CRITICAL: auth.admin.deleteUser must NEVER be called when DB RPC fails");
});

// ============================================================================
// 2. STORAGE FAILURE & PAGINATION TESTS
// ============================================================================

Deno.test("Storage Failure: Storage listing failure fails closed (500) and NEVER calls auth.admin.deleteUser", async () => {
  const userId = "44444444-4444-4444-4444-444444444444";
  let authDeleteCalled = false;

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async () => ({ data: null, error: null }),
  };

  const mockAdminClient = {
    storage: {
      from: () => ({
        list: async () => ({
          data: null,
          error: { message: "Internal storage S3 provider unreachable" },
        }),
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
  assert(data.error.includes("Failed to clean up user storage objects. Account deletion aborted."));
  assertEquals(authDeleteCalled, false, "CRITICAL: auth.admin.deleteUser must NEVER be called when storage list fails");
});

Deno.test("Storage Failure: Storage removal failure fails closed (500) and NEVER calls auth.admin.deleteUser", async () => {
  const userId = "55555555-5555-5555-5555-555555555555";
  let authDeleteCalled = false;

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async () => ({ data: null, error: null }),
  };

  const mockAdminClient = {
    storage: {
      from: () => ({
        list: async () => ({
          data: [{ name: "avatar.png", id: "f-1" }],
          error: null,
        }),
        remove: async () => ({
          data: null,
          error: { message: "Permission denied on storage remove" },
        }),
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
  assert(data.error.includes("Failed to clean up user storage objects. Account deletion aborted."));
  assertEquals(authDeleteCalled, false, "CRITICAL: auth.admin.deleteUser must NEVER be called when storage remove fails");
});

Deno.test("Storage Unit: listAllStorageFiles paginates across multiple pages correctly", async () => {
  // Simulate 150 files across 2 pages (page 1: 100 files, page 2: 50 files)
  const page1Files = Array.from({ length: 100 }, (_, i) => ({ name: `file_${i}.jpg`, id: `id-${i}` }));
  const page2Files = Array.from({ length: 50 }, (_, i) => ({ name: `file_${100 + i}.jpg`, id: `id-${100 + i}` }));

  const mockStorage = {
    from: () => ({
      list: async (_folder: string, opts: { offset: number; limit: number }) => {
        if (opts.offset === 0) {
          return { data: page1Files, error: null };
        } else if (opts.offset === 100) {
          return { data: page2Files, error: null };
        }
        return { data: [], error: null };
      },
    }),
  };

  const { files, error } = await listAllStorageFiles(mockStorage, "talkmate", "users/test-user");
  assertEquals(error, null);
  assertEquals(files.length, 150, "Should have discovered exactly 150 files across both pages");
  assertEquals(files[0], "users/test-user/file_0.jpg");
  assertEquals(files[149], "users/test-user/file_149.jpg");
});

Deno.test("Storage Unit: listAllStorageFiles traverses nested folders correctly", async () => {
  const mockStorage = {
    from: () => ({
      list: async (folder: string) => {
        if (folder === "users/user-123") {
          return {
            data: [
              { name: "root_avatar.png", id: "file-1" },
              { name: "documents", id: null, metadata: null }, // folder
            ],
            error: null,
          };
        } else if (folder === "users/user-123/documents") {
          return {
            data: [
              { name: "passport.pdf", id: "file-2" },
            ],
            error: null,
          };
        }
        return { data: [], error: null };
      },
    }),
  };

  const { files, error } = await listAllStorageFiles(mockStorage, "talkmate", "users/user-123");
  assertEquals(error, null);
  assertEquals(files.length, 2);
  assert(files.includes("users/user-123/root_avatar.png"));
  assert(files.includes("users/user-123/documents/passport.pdf"));
});

// ============================================================================
// 3. AUTH FAILURE & IDEMPOTENT RECOVERY TESTS
// ============================================================================

Deno.test("Auth Failure: GoTrue service error returns 500 error", async () => {
  const userId = "66666666-6666-6666-6666-666666666666";

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async () => ({ data: null, error: null }),
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
        deleteUser: async () => ({
          data: { user: null },
          error: { message: "Internal server error 500: Database unavailable", status: 500 },
        }),
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
  assert(data.error.includes("Failed to complete authentication identity deletion"));
});

Deno.test("Auth Recovery: Idempotent retry when Auth user is already deleted ('not found') succeeds (200)", async () => {
  const userId = "77777777-7777-7777-7777-777777777777";

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async () => ({ data: null, error: null }),
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
        deleteUser: async () => ({
          data: { user: null },
          error: { message: "User not found", status: 404 },
        }),
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
  assert(data.message.includes("successfully deleted"));
});

Deno.test("Full Success: Clean end-to-end deletion with Storage files and Auth removal", async () => {
  const userId = "88888888-8888-8888-8888-888888888888";
  let rpcCalled = false;
  let deletedPaths: string[] = [];
  let deletedAuthUserId = "";

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: "user@test.com" } },
        error: null,
      }),
    },
    rpc: async (fnName: string) => {
      assertEquals(fnName, "delete_user_account");
      rpcCalled = true;
      return { data: null, error: null };
    },
  };

  const mockAdminClient = {
    storage: {
      from: () => ({
        list: async () => ({
          data: [{ name: "avatar.jpg", id: "f-1" }],
          error: null,
        }),
        remove: async (paths: string[]) => {
          deletedPaths = paths;
          return { data: paths, error: null };
        },
      }),
    },
    auth: {
      admin: {
        deleteUser: async (id: string) => {
          deletedAuthUserId = id;
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
  assertEquals(rpcCalled, true);
  assertEquals(deletedPaths, [`users/${userId}/avatar.jpg`]);
  assertEquals(deletedAuthUserId, userId);
});

Deno.test("HTTP Method: Non-POST methods return 405 Method Not Allowed", async () => {
  for (const method of ["GET", "PUT", "DELETE", "PATCH"]) {
    const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
      method,
      headers: { "Content-Type": "application/json" },
    });
    const res = await handleDeleteAccount(req, MOCK_CONFIG);
    assertEquals(res.status, 405);
  }
});
