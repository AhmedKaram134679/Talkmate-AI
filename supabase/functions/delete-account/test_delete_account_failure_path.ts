// TalkMate AI - Complete Account Deletion Security & Fail-Closed Unit Test Suite
// Verifies Section 5 & 8 requirements:
// - Deterministic fail-closed database RPC handling
// - Storage file/folder classification based on official Supabase Storage API semantics
// - Recursive traversal: files with/without extensions, multiple dots, spaces, Unicode, empty folders
// - Safe handling of pagination and duplicate results
// - Strict operational ceiling of 2000 files (fails closed if exceeded)
// - Realistic authentication lifecycle: dead JWT rejected with 401 after Auth deletion
// - Valid retry when Auth deletion failed in run 1
// - Zero partial deletions: Auth identity is NEVER deleted if DB or Storage fails

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
// 2. STORAGE CLASSIFICATION, PAGINATION & CEILING TESTS (Section 8)
// ============================================================================

Deno.test("Storage Classification: Correctly distinguishes files and folders without extension heuristics", async () => {
  const mockStorage = {
    from: () => ({
      list: async (folder: string) => {
        if (folder === "users/u-1") {
          return {
            data: [
              // Files: must have non-null id
              { name: "avatar.jpg", id: "uuid-1" },
              { name: "Makefile", id: "uuid-2" }, // File with NO extension
              { name: "backup.tar.gz", id: "uuid-3" }, // File with multiple dots
              { name: "my voice note.m4a", id: "uuid-4" }, // File with spaces
              { name: "صوتي.mp3", id: "uuid-5" }, // Unicode filename
              // Folders: have id === null
              { name: "media_folder", id: null },
              { name: "my.dot.folder", id: null }, // Folder WITH dot in name
            ],
            error: null,
          };
        } else if (folder === "users/u-1/media_folder") {
          return {
            data: [
              { name: "clip.mp4", id: "uuid-6" },
            ],
            error: null,
          };
        } else if (folder === "users/u-1/my.dot.folder") {
          return {
            data: [
              { name: "nested_no_ext", id: "uuid-7" },
            ],
            error: null,
          };
        }
        return { data: [], error: null };
      },
    }),
  };

  const { files, error } = await listAllStorageFiles(mockStorage, "talkmate", "users/u-1");
  assertEquals(error, null);
  assertEquals(files.length, 7);
  assert(files.includes("users/u-1/avatar.jpg"));
  assert(files.includes("users/u-1/Makefile"), "File without extension must be classified as file");
  assert(files.includes("users/u-1/backup.tar.gz"), "File with multiple dots must be classified as file");
  assert(files.includes("users/u-1/my voice note.m4a"), "File with spaces must be classified as file");
  assert(files.includes("users/u-1/صوتي.mp3"), "Unicode file must be classified as file");
  assert(files.includes("users/u-1/media_folder/clip.mp4"), "Nested folder file must be found");
  assert(files.includes("users/u-1/my.dot.folder/nested_no_ext"), "Folder with dot in name must be traversed as folder");
});

Deno.test("Storage Pagination: listAllStorageFiles paginates across multiple pages correctly", async () => {
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
  assertEquals(files.length, 150);
});

Deno.test("Storage Loops: Repeated pagination and duplicate entries do not cause infinite recursion", async () => {
  let callCount = 0;
  const mockStorage = {
    from: () => ({
      list: async (folder: string) => {
        callCount++;
        if (callCount > 10) {
          throw new Error("Infinite loop detected!");
        }
        if (folder === "users/loop-user") {
          return {
            data: [
              { name: "subfolder", id: null },
            ],
            error: null,
          };
        } else if (folder === "users/loop-user/subfolder") {
          return {
            data: [
              // Storage backend returning empty or already traversed folder
              { name: ".emptyFolderPlaceholder", id: null },
            ],
            error: null,
          };
        }
        return { data: [], error: null };
      },
    }),
  };

  const { files, error } = await listAllStorageFiles(mockStorage, "talkmate", "users/loop-user");
  assertEquals(error, null);
  assertEquals(files.length, 0);
  assert(callCount <= 3, "Traversal must terminate promptly without looping");
});

Deno.test("Storage Ceiling: Exactly 2000 files succeeds; >2000 files fails closed", async () => {
  // 1. Exactly 2000 files
  const mock2000 = {
    from: () => ({
      list: async (_folder: string, opts: { offset: number }) => {
        if (opts.offset < 2000) {
          const batch = Array.from({ length: 100 }, (_, i) => ({
            name: `file_${opts.offset + i}.jpg`,
            id: `id-${opts.offset + i}`,
          }));
          return { data: batch, error: null };
        }
        return { data: [], error: null };
      },
    }),
  };

  const res2000 = await listAllStorageFiles(mock2000, "talkmate", "users/u-2000");
  assertEquals(res2000.error, null);
  assertEquals(res2000.files.length, 2000);

  // 2. 2001 files (exceeds operational ceiling)
  const mock2001 = {
    from: () => ({
      list: async (_folder: string, opts: { offset: number }) => {
        if (opts.offset <= 2000) {
          const size = opts.offset === 2000 ? 1 : 100;
          const batch = Array.from({ length: size }, (_, i) => ({
            name: `file_${opts.offset + i}.jpg`,
            id: `id-${opts.offset + i}`,
          }));
          return { data: batch, error: null };
        }
        return { data: [], error: null };
      },
    }),
  };

  const res2001 = await listAllStorageFiles(mock2001, "talkmate", "users/u-2001");
  assert(res2001.error !== null);
  assert(
    (res2001.error as Error).message.includes("Storage discovery exceeded operational limit of 2000 files")
  );
});

Deno.test("Storage Failure in Handler: Nested folder list failure fails closed (500) and aborts Auth deletion", async () => {
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
        list: async (folder: string) => {
          if (folder.includes("subfolder")) {
            return { data: null, error: { message: "S3 list failure in nested folder" } };
          }
          return {
            data: [{ name: "subfolder", id: null }],
            error: null,
          };
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
  assert(data.error.includes("Failed to clean up user storage objects. Account deletion aborted."));
  assertEquals(authDeleteCalled, false, "Auth deletion must NEVER be called when nested storage fails");
});

Deno.test("Storage Failure in Handler: Removal failure fails closed (500) and aborts Auth deletion", async () => {
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
          data: [{ name: "voice.m4a", id: "uuid-1" }],
          error: null,
        }),
        remove: async () => ({
          data: null,
          error: { message: "S3 deleteObjects forbidden" },
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
  assertEquals(authDeleteCalled, false, "Auth deletion must NEVER be called when storage removal fails");
});

// ============================================================================
// 3. AUTH FAILURE & REALISTIC LIFECYCLE TESTS (Section 5)
// ============================================================================

Deno.test("Auth Failure: GoTrue admin delete failure fails closed (500)", async () => {
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

Deno.test("Real Lifecycle: Subsequent request after Auth identity was deleted is rejected (401)", async () => {
  // When an account has been deleted from Supabase Auth, subsequent requests with the old JWT
  // fail authentication in GoTrue (auth.getUser returns null user and 401 error).
  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: "User not found or session revoked", status: 401 },
      }),
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer dead_user_jwt_after_deletion",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });

  const res = await handleDeleteAccount(req, {
    ...MOCK_CONFIG,
    userClient: mockUserClient,
  });

  assertEquals(res.status, 401, "Dead JWT after account deletion must be rejected with 401");
  const data = await res.json();
  assert(data.error.includes("Invalid or expired session"));
});

Deno.test("Real Lifecycle: Safe retry when run 1 failed at Auth deletion succeeds on retry", async () => {
  // If run 1 succeeded on DB and Storage, but failed on network to GoTrue admin API:
  // The Auth identity still exists in GoTrue, so user JWT is STILL VALID!
  const userId = "77777777-7777-7777-7777-777777777777";
  let rpcCalled = false;
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
      rpcCalled = true;
      // DB cleanup is idempotent (no-op since rows already deleted)
      return { data: null, error: null };
    },
  };

  const mockAdminClient = {
    storage: {
      from: () => ({
        // Storage is already clean (0 files found)
        list: async () => ({ data: [], error: null }),
        remove: async () => ({ data: [], error: null }),
      }),
    },
    auth: {
      admin: {
        deleteUser: async (id: string) => {
          assertEquals(id, userId);
          authDeleteCalled = true;
          return { data: { user: null }, error: null };
        },
      },
    },
  };

  const req = new Request("https://mock.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: {
      "Authorization": "Bearer valid_retry_jwt",
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
  assertEquals(authDeleteCalled, true);
});

Deno.test("Concurrent Requests: Concurrent deletion requests for the same user handle race conditions safely", async () => {
  const userId = "99999999-9999-9999-9999-999999999999";
  let authDeleteCount = 0;

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
        deleteUser: async () => {
          authDeleteCount++;
          if (authDeleteCount === 1) {
            return { data: { user: null }, error: null };
          } else {
            // Subsequent concurrent call sees user already deleted
            return { data: { user: null }, error: { message: "User not found", status: 404 } };
          }
        },
      },
    },
  };

  const createReq = () =>
    new Request("https://mock.supabase.co/functions/v1/delete-account", {
      method: "POST",
      headers: {
        "Authorization": "Bearer valid_user_jwt",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

  const [res1, res2] = await Promise.all([
    handleDeleteAccount(createReq(), { ...MOCK_CONFIG, userClient: mockUserClient, adminClient: mockAdminClient }),
    handleDeleteAccount(createReq(), { ...MOCK_CONFIG, userClient: mockUserClient, adminClient: mockAdminClient }),
  ]);

  assertEquals(res1.status, 200);
  assertEquals(res2.status, 200);
  const data1 = await res1.json();
  const data2 = await res2.json();
  assertEquals(data1.success, true);
  assertEquals(data2.success, true);
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
          data: [{ name: "avatar.jpg", id: "uuid-1" }],
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
