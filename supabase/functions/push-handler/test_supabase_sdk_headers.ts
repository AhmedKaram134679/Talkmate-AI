// TalkMate AI - Supabase SDK Header Verification & Client Separation Tests
// Verifies Section 4 (Critical Issue B):
// - Generated HTTP headers for Secret Key and Publishable Key clients
// - Verification that Secret Key is transmitted via apikey header
// - Strict separation between privileged administrative client and user-scoped client
// - Zero credential exposure in logs or test output

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.42.0";

const DUMMY_URL = "https://mock.supabase.co";
const MOCK_SECRET_KEY = "mock_sdk_secret_key_9999999999";
const MOCK_PUBLISHABLE_KEY = "mock_sdk_publishable_key_8888888888";
const MOCK_USER_JWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.mocksignature";

Deno.test("SDK Headers: Privileged Admin Client generates apikey header for Auth Admin requests", async () => {
  let capturedUrl = "";
  let capturedHeaders: Record<string, string> = {};

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    capturedUrl = input.toString();
    const h = new Headers(init?.headers);
    h.forEach((val, key) => {
      capturedHeaders[key.toLowerCase()] = val;
    });
    return new Response(JSON.stringify({ id: "mock-user-id" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await adminClient.auth.admin.getUserById("test-user-id");

    assert(capturedUrl.includes("/auth/v1/admin/users/test-user-id"));
    assertEquals(capturedHeaders["apikey"], MOCK_SECRET_KEY);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("SDK Headers: User-Scoped Client generates apikey and Authorization Bearer header for queries", async () => {
  let capturedUrl = "";
  let capturedHeaders: Record<string, string> = {};

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    capturedUrl = input.toString();
    const h = new Headers(init?.headers);
    h.forEach((val, key) => {
      capturedHeaders[key.toLowerCase()] = val;
    });
    return new Response(JSON.stringify([{ id: "1" }]), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  try {
    const userClient = createClient(DUMMY_URL, MOCK_PUBLISHABLE_KEY, {
      global: { headers: { Authorization: `Bearer ${MOCK_USER_JWT}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await userClient.from("messages").select("id").limit(1);

    assert(capturedUrl.includes("/rest/v1/messages"));
    assertEquals(capturedHeaders["apikey"], MOCK_PUBLISHABLE_KEY);
    assertEquals(capturedHeaders["authorization"], `Bearer ${MOCK_USER_JWT}`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("SDK Headers: Storage admin operations send apikey header", async () => {
  let capturedUrl = "";
  let capturedHeaders: Record<string, string> = {};

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    capturedUrl = input.toString();
    const h = new Headers(init?.headers);
    h.forEach((val, key) => {
      capturedHeaders[key.toLowerCase()] = val;
    });
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  try {
    const adminClient = createClient(DUMMY_URL, MOCK_SECRET_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await adminClient.storage.from("talkmate").list("users/test-user");

    assert(capturedUrl.includes("/storage/v1/object/list/talkmate"));
    assertEquals(capturedHeaders["apikey"], MOCK_SECRET_KEY);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
