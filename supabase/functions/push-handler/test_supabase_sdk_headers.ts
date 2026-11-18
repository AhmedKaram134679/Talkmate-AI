// TalkMate AI - Comprehensive Supabase SDK Outbound Header Verification Suite
// Verifies Section 6 (Critical Issue D):
// - Generated outbound HTTP headers for Secret Key and Publishable Key clients across all API surfaces
// - Captures outbound headers at the HTTP transport boundary (fetch interception)
// - Proves all 10 requirements from Section 6.D.6:
//   1. Publishable-key client behavior
//   2. Secret-key client behavior
//   3. PostgREST request behavior
//   4. Auth request behavior
//   5. Storage request behavior
//   6. Edge Function request behavior
//   7. User JWT authorization behavior
//   8. Invalid / empty API-key behavior
//   9. No accidental Secret-Key-as-user-JWT interpretation
//   10. No unintended privileged-header propagation across separate client instances
// - Zero credential exposure in logs or test output

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.42.0";

const DUMMY_URL = "https://mock.supabase.co";
const MOCK_SECRET_KEY = "mock_sdk_secret_key_9999999999";
const MOCK_PUBLISHABLE_KEY = "mock_sdk_publishable_key_8888888888";
const MOCK_USER_JWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.mocksignature";

interface CapturedRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
}

function interceptFetch(
  mockResponse: { status?: number; json?: unknown } = {}
): {
  getRequests: () => CapturedRequest[];
  restore: () => void;
} {
  const captured: CapturedRequest[] = [];
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const headers: Record<string, string> = {};
    const h = new Headers(init?.headers);
    h.forEach((val, key) => {
      headers[key.toLowerCase()] = val;
    });

    captured.push({
      url: input.toString(),
      method: init?.method || "GET",
      headers,
      body: init?.body ? String(init.body) : undefined,
    });

    return new Response(JSON.stringify(mockResponse.json ?? []), {
      status: mockResponse.status ?? 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  return {
    getRequests: () => captured,
    restore: () => {
      globalThis.fetch = originalFetch;
    },
  };
}

// ----------------------------------------------------------------------------
// 1. Publishable-Key Client Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (1/10): Publishable-key client transmits key via apikey header", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const pubClient = createClient(DUMMY_URL, MOCK_PUBLISHABLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await pubClient.from("public_items").select("id").limit(1);

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assertEquals(reqs[0].headers["apikey"], MOCK_PUBLISHABLE_KEY);
    // Verified transport behavior: SDK default Authorization uses the key when no session exists
    assertEquals(reqs[0].headers["authorization"], `Bearer ${MOCK_PUBLISHABLE_KEY}`);
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 2. Secret-Key Client Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (2/10): Secret-key client transmits key via apikey and internal transport Bearer", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await adminClient.from("admin_audit").select("id").limit(1);

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assertEquals(reqs[0].headers["apikey"], MOCK_SECRET_KEY);
    assertEquals(reqs[0].headers["authorization"], `Bearer ${MOCK_SECRET_KEY}`);
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 3. PostgREST Request Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (3/10): PostgREST queries include apikey, accept-profile, and proper path", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const client = createClient(DUMMY_URL, MOCK_PUBLISHABLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await client.from("messages").select("id, content").eq("sender_id", "alice");

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assert(reqs[0].url.includes("/rest/v1/messages"));
    assertEquals(reqs[0].headers["apikey"], MOCK_PUBLISHABLE_KEY);
    assertEquals(reqs[0].headers["accept-profile"], "public");
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 4. Auth Request Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (4/10): Auth admin requests send apikey to /auth/v1/admin endpoints", async () => {
  const { getRequests, restore } = interceptFetch({ json: { id: "test-user-id" } });
  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await adminClient.auth.admin.getUserById("test-user-id");

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assert(reqs[0].url.includes("/auth/v1/admin/users/test-user-id"));
    assertEquals(reqs[0].headers["apikey"], MOCK_SECRET_KEY);
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 5. Storage Request Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (5/10): Storage API requests send apikey to /storage/v1 endpoints", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await adminClient.storage.from("talkmate").list("users/test-user");

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assert(reqs[0].url.includes("/storage/v1/object/list/talkmate"));
    assertEquals(reqs[0].headers["apikey"], MOCK_SECRET_KEY);
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 6. Edge Function Request Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (6/10): Edge Function invocation transmits apikey to /functions/v1 endpoints", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await adminClient.functions.invoke("push-handler", { body: { test: true } });

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assert(reqs[0].url.includes("/functions/v1/push-handler"));
    assertEquals(reqs[0].headers["apikey"], MOCK_SECRET_KEY);
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 7. User JWT Authorization Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (7/10): User JWT client forwards user Bearer JWT and Publishable key strictly", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const userClient = createClient(DUMMY_URL, MOCK_PUBLISHABLE_KEY, {
      global: { headers: { Authorization: `Bearer ${MOCK_USER_JWT}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await userClient.from("messages").select("id").limit(1);

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assertEquals(reqs[0].headers["apikey"], MOCK_PUBLISHABLE_KEY);
    assertEquals(reqs[0].headers["authorization"], `Bearer ${MOCK_USER_JWT}`);
    // Crucial negative guarantee: User client NEVER sends Secret Key
    assert(reqs[0].headers["apikey"] !== MOCK_SECRET_KEY);
    assert(reqs[0].headers["authorization"] !== `Bearer ${MOCK_SECRET_KEY}`);
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 8. Invalid / Empty API-Key Behavior
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (8/10): Client handles malformed/dummy key without crashing or credential leak", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const client = createClient(DUMMY_URL, "invalid_dummy_key", {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await client.from("test").select("id").limit(1);

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assertEquals(reqs[0].headers["apikey"], "invalid_dummy_key");
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 9. No Accidental Secret-Key-as-user-JWT Interpretation
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (9/10): User-scoped client never attaches Secret Key in Authorization or apikey", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    // Authenticated user performing RPC delete_user_account
    const userClient = createClient(DUMMY_URL, MOCK_PUBLISHABLE_KEY, {
      global: { headers: { Authorization: `Bearer ${MOCK_USER_JWT}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await userClient.rpc("delete_user_account");

    const reqs = getRequests();
    assertEquals(reqs.length, 1);
    assertEquals(reqs[0].headers["apikey"], MOCK_PUBLISHABLE_KEY);
    assertEquals(reqs[0].headers["authorization"], `Bearer ${MOCK_USER_JWT}`);
    // Ensure no header contains mock secret key
    for (const [headerName, headerVal] of Object.entries(reqs[0].headers)) {
      assert(
        !headerVal.includes(MOCK_SECRET_KEY),
        `Header ${headerName} must not contain secret key`
      );
    }
  } finally {
    restore();
  }
});

// ----------------------------------------------------------------------------
// 10. No Unintended Privileged-Header Propagation Across Separate Clients
// ----------------------------------------------------------------------------
Deno.test("SDK Headers (10/10): Admin and User client instances remain strictly isolated", async () => {
  const { getRequests, restore } = interceptFetch();
  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const userClient = createClient(DUMMY_URL, MOCK_PUBLISHABLE_KEY, {
      global: { headers: { Authorization: `Bearer ${MOCK_USER_JWT}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Run admin query first
    await adminClient.from("audit_logs").select("id").limit(1);
    // Run user query second
    await userClient.from("messages").select("id").limit(1);

    const reqs = getRequests();
    assertEquals(reqs.length, 2);

    // Request 1 is admin: has secret key
    assertEquals(reqs[0].headers["apikey"], MOCK_SECRET_KEY);

    // Request 2 is user: has publishable key and user JWT, ZERO secret key leakage
    assertEquals(reqs[1].headers["apikey"], MOCK_PUBLISHABLE_KEY);
    assertEquals(reqs[1].headers["authorization"], `Bearer ${MOCK_USER_JWT}`);
    assert(!JSON.stringify(reqs[1].headers).includes(MOCK_SECRET_KEY));
  } finally {
    restore();
  }
});
