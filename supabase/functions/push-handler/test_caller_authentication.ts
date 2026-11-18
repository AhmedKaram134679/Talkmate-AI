// TalkMate AI - Edge Function Caller Authentication & Identity Boundary Unit Tests
// Verifies Section 3.A.4 matrix: Mutual exclusivity of Secret Key admin path and User JWT path.

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const MOCK_SECRET_KEY = "mock_secret_key_test_1234567890";
const MOCK_PUBLISHABLE_KEY = "mock_publishable_key_test_abcdef";

// Set required module-level environment variables before importing push-handler
Deno.env.set("SUPABASE_URL", "https://mock.supabase.co");
Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: MOCK_SECRET_KEY }));
Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: MOCK_PUBLISHABLE_KEY }));

// Load valid local test service account
try {
  const serviceAccountJson = Deno.readTextFileSync(new URL("./service-account.json", import.meta.url));
  Deno.env.set("FIREBASE_SERVICE_ACCOUNT_B64", btoa(serviceAccountJson));
} catch (_) {}

const { handlePushRequest } = await import("./index.ts");

const authenticUserId = "11111111-1111-1111-1111-111111111111";
const otherUserId = "22222222-2222-2222-2222-222222222222";

function createMockAdminClient(opts?: {
  validUserJwt?: string;
  expiredUserJwt?: string;
  userRole?: string;
  callsMock?: any;
}) {
  return {
    auth: {
      getUser: async (token: string) => {
        if (opts?.validUserJwt && token === opts.validUserJwt) {
          return {
            data: {
              user: {
                id: authenticUserId,
                email: "user@test.com",
                role: opts.userRole || "authenticated",
              },
            },
            error: null,
          };
        }
        if (opts?.expiredUserJwt && token === opts.expiredUserJwt) {
          return {
            data: { user: null },
            error: { message: "Token expired", status: 401 },
          };
        }
        return {
          data: { user: null },
          error: { message: "Invalid JWT token", status: 401 },
        };
      },
    },
    from: (table: string) => {
      if (table === "calls" && opts?.callsMock) {
        return opts.callsMock;
      }
      return {
        select: () => ({
          eq: () => ({
            single: async () => ({ data: null, error: { message: "Not found" } }),
          }),
        }),
      };
    },
  };
}

Deno.test("Scenario 1: Valid Secret Key in apikey (no bearer token) succeeds as administrative caller", async () => {
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_SECRET_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient(),
  });

  // Administrative caller reaches handler body; status is not 401
  assert(res.status !== 401, `Expected admin authorization, received: ${res.status}`);
});

Deno.test("Scenario 2: Invalid Secret Key in apikey is rejected (401)", async () => {
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": "wrong_invalid_secret_key",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient(),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(data.error.toLowerCase().includes("missing or invalid authorization header"));
});

Deno.test("Scenario 3: Missing apikey and missing bearer token is rejected (401)", async () => {
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient(),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(data.error.toLowerCase().includes("missing or invalid authorization header"));
});

Deno.test("Scenario 4: Publishable Key without valid user JWT is rejected (401)", async () => {
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_PUBLISHABLE_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient(),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(data.error.toLowerCase().includes("missing or invalid authorization header"));
});

Deno.test("Scenario 5: Publishable Key with valid user JWT succeeds user authentication", async () => {
  const validJwt = "valid_user_jwt_token_12345";
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_PUBLISHABLE_KEY,
      "Authorization": `Bearer ${validJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient({ validUserJwt: validJwt }),
  });

  // User was authenticated; status is not 401 Unauthorized
  assert(res.status !== 401, `Expected user authorization, received: ${res.status}`);
});

Deno.test("Scenario 6: Invalid user JWT is rejected (401)", async () => {
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_PUBLISHABLE_KEY,
      "Authorization": "Bearer invalid_malformed_jwt_token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient(),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(data.error.includes("Invalid JWT token"));
});

Deno.test("Scenario 7: Expired user JWT is rejected (401)", async () => {
  const expiredJwt = "expired_user_jwt_token_99999";
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_PUBLISHABLE_KEY,
      "Authorization": `Bearer ${expiredJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient({ expiredUserJwt: expiredJwt }),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(data.error.includes("Invalid JWT token"));
});

Deno.test("Scenario 8: Secret Key supplied only as Bearer token is rejected (401)", async () => {
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${MOCK_SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "ping" }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient(),
  });

  assertEquals(res.status, 401);
  const data = await res.json();
  assert(
    data.error.includes("Secret key must be supplied via apikey header, not Bearer token"),
    `Expected specific rejection message, received: ${data.error}`
  );
});

Deno.test("Scenario 9: Authenticated user attempting call push without call record is rejected (403)", async () => {
  const validJwt = "valid_user_jwt_token_12345";
  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_PUBLISHABLE_KEY,
      "Authorization": `Bearer ${validJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      type: "call_ringing",
      receiver_id: otherUserId,
      // Missing call_id
    }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient({ validUserJwt: validJwt }),
  });

  assertEquals(res.status, 403);
  const data = await res.json();
  assert(data.error.includes("Missing call record identifier"));
});

Deno.test("Scenario 10: User A attempting to trigger call push for User B's call is rejected (403)", async () => {
  const validJwt = "valid_user_jwt_token_12345";
  const mockCalls = {
    select: () => ({
      eq: () => ({
        single: async () => ({
          data: {
            id: "call-999",
            sender_id: otherUserId, // Call belongs to someone else (User B)
            receiver_id: "33333333-3333-3333-3333-333333333333",
            status: "ringing",
          },
          error: null,
        }),
      }),
    }),
  };

  const req = new Request("https://mock.supabase.co/functions/v1/push-handler", {
    method: "POST",
    headers: {
      "apikey": MOCK_PUBLISHABLE_KEY,
      "Authorization": `Bearer ${validJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      type: "call_ringing",
      call_id: "call-999",
      receiver_id: "33333333-3333-3333-3333-333333333333",
    }),
  });

  const res = await handlePushRequest(req, {
    secretKey: MOCK_SECRET_KEY,
    adminClient: createMockAdminClient({
      validUserJwt: validJwt,
      callsMock: mockCalls,
    }),
  });

  assertEquals(res.status, 403);
  const data = await res.json();
  assert(data.error.includes("Caller does not match call sender"));
});
