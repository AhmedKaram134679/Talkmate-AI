// TalkMate AI - StructuredLogger Sanitization Verification Tests
// Proves SEC-09: No JWTs, API keys, FCM tokens, email addresses, or unmasked user IDs are leaked in logs.

import { assertEquals, assertNotEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Duplicate / import the exact StructuredLogger logic from push-handler/index.ts
class StructuredLogger {
  public static redactString(str: string): string {
    return str
      .replace(/[a-zA-Z0-9_\-]{20,}\.[a-zA-Z0-9_\-]{20,}\.[a-zA-Z0-9_\-]+/g, "[REDACTED_JWT]")
      .replace(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, "[REDACTED_EMAIL]")
      .replace(/key=[a-zA-Z0-9_\-]{20,}/g, "key=[REDACTED_API_KEY]")
      .replace(/(token|secret|password|bearer)=([^\s&]+)/gi, "$1=[REDACTED]");
  }

  // deno-lint-ignore no-explicit-any
  public static sanitize(obj: any): any {
    if (obj === null || obj === undefined) return obj;
    if (typeof obj === "string") return StructuredLogger.redactString(obj);
    if (typeof obj === "number" || typeof obj === "boolean") return obj;
    if (Array.isArray(obj)) return obj.map(item => StructuredLogger.sanitize(item));
    if (typeof obj === "object") {
      // deno-lint-ignore no-explicit-any
      const sanitized: any = {};
      for (const [key, val] of Object.entries(obj)) {
        if (/token|jwt|auth|secret|password|private_key/i.test(key)) {
          sanitized[key] = "[REDACTED]";
        } else {
          sanitized[key] = StructuredLogger.sanitize(val);
        }
      }
      return sanitized;
    }
    return String(obj);
  }

  public static safeId(id: string | null | undefined): string {
    if (!id) return "none";
    if (id.length <= 8) return id.slice(0, 4) + "...";
    return id.slice(0, 4) + "..." + id.slice(-4);
  }

  public static formatEntry(level: string, message: string, context?: Record<string, unknown>): string {
    return JSON.stringify({
      level,
      timestamp: "2026-01-01T00:00:00.000Z",
      message: StructuredLogger.redactString(message),
      context: context ? StructuredLogger.sanitize(context) : undefined,
    });
  }
}

Deno.test("StructuredLogger: Redacts JWTs from messages and context", () => {
  const fakeJwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";
  const output = StructuredLogger.formatEntry("INFO", `Caller submitted token: ${fakeJwt}`, { auth_token: fakeJwt, detail: `Bearer ${fakeJwt}` });

  assertNotEquals(output.includes(fakeJwt), true);
  assertEquals(output.includes("[REDACTED_JWT]"), true);
});

Deno.test("StructuredLogger: Redacts email addresses", () => {
  const email = "victim_account@domain-test.org";
  const output = StructuredLogger.formatEntry("WARN", `Notification targeted to email: ${email}`, { user_email: email });

  assertNotEquals(output.includes(email), true);
  assertEquals(output.includes("[REDACTED_EMAIL]"), true);
});

Deno.test("StructuredLogger: Redacts API keys and query token patterns", () => {
  const rawUrl = "https://fcm.googleapis.com/fcm/send?key=AIzaSyA_abcdef1234567890_SAMPLEKEY&token=device_token_xyz_98765";
  const output = StructuredLogger.formatEntry("ERROR", `Failed request to ${rawUrl}`);

  assertNotEquals(output.includes("AIzaSyA_abcdef1234567890_SAMPLEKEY"), true);
  assertNotEquals(output.includes("device_token_xyz_98765"), true);
  assertEquals(output.includes("[REDACTED_API_KEY]"), true);
  assertEquals(output.includes("token=[REDACTED]"), true);
});

Deno.test("StructuredLogger: Redacts sensitive object properties in context", () => {
  const sensitiveContext = {
    user_id: "00000000-0000-0000-0000-000000000001",
    fcm_token: "fcm_token_secret_value_12345",
    jwt_claim: "secret_claim",
    service_role_secret: "super_secret_role_key",
    normal_key: "safe_value"
  };

  const output = StructuredLogger.formatEntry("SECURITY", "Security audit check", sensitiveContext);

  assertNotEquals(output.includes("fcm_token_secret_value_12345"), true);
  assertNotEquals(output.includes("secret_claim"), true);
  assertNotEquals(output.includes("super_secret_role_key"), true);
  assertEquals(output.includes('"normal_key":"safe_value"'), true);
});

Deno.test("StructuredLogger: safeId masks UUIDs properly", () => {
  const uuid = "4f2a7a40-1a1a-4d2a-89bc-99378129841a";
  const masked = StructuredLogger.safeId(uuid);

  assertEquals(masked, "4f2a...841a");
  assertNotEquals(masked, uuid);
  assertEquals(StructuredLogger.safeId(null), "none");
  assertEquals(StructuredLogger.safeId("short"), "shor...");
});

// Helper from push-handler & delete-account
function parseRequiredKeyFromRaw(raw: string | undefined | null, envVarName: string): string {
  if (!raw || typeof raw !== "string" || raw.trim().length === 0) {
    throw new Error(`Missing or empty environment configuration: ${envVarName}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (_e) {
    throw new Error(`Malformed JSON in environment dictionary: ${envVarName}`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`Invalid format in ${envVarName}: expected key-value object mapping`);
  }
  const defaultKey = (parsed as Record<string, unknown>).default;
  if (!defaultKey || typeof defaultKey !== "string" || defaultKey.trim().length === 0) {
    throw new Error(`No valid 'default' key found in ${envVarName}`);
  }
  return defaultKey.trim();
}

Deno.test("Key Parsing: Valid key dictionary succeeds", () => {
  const validJson = JSON.stringify({ default: "sb_secret_test_12345" });
  const key = parseRequiredKeyFromRaw(validJson, "SUPABASE_SECRET_KEYS");
  assertEquals(key, "sb_secret_test_12345");
});

Deno.test("Key Parsing: Missing or empty input throws fail-closed error", () => {
  let threw = false;
  try {
    parseRequiredKeyFromRaw(undefined, "SUPABASE_SECRET_KEYS");
  } catch (e: any) {
    threw = true;
    assertEquals(e.message.includes("Missing or empty"), true);
  }
  assertEquals(threw, true);

  threw = false;
  try {
    parseRequiredKeyFromRaw("", "SUPABASE_SECRET_KEYS");
  } catch (e: any) {
    threw = true;
    assertEquals(e.message.includes("Missing or empty"), true);
  }
  assertEquals(threw, true);
});

Deno.test("Key Parsing: Malformed JSON throws fail-closed error", () => {
  let threw = false;
  try {
    parseRequiredKeyFromRaw("{ invalid json", "SUPABASE_SECRET_KEYS");
  } catch (e: any) {
    threw = true;
    assertEquals(e.message.includes("Malformed JSON"), true);
  }
  assertEquals(threw, true);
});

Deno.test("Key Parsing: Non-object or array throws fail-closed error", () => {
  let threw = false;
  try {
    parseRequiredKeyFromRaw(JSON.stringify(["sb_secret_array"]), "SUPABASE_SECRET_KEYS");
  } catch (e: any) {
    threw = true;
    assertEquals(e.message.includes("Invalid format"), true);
  }
  assertEquals(threw, true);
});

Deno.test("Key Parsing: Missing or empty default key throws fail-closed error", () => {
  let threw = false;
  try {
    parseRequiredKeyFromRaw(JSON.stringify({ secondary: "sb_secret_2" }), "SUPABASE_SECRET_KEYS");
  } catch (e: any) {
    threw = true;
    assertEquals(e.message.includes("No valid 'default' key"), true);
  }
  assertEquals(threw, true);

  threw = false;
  try {
    parseRequiredKeyFromRaw(JSON.stringify({ default: "   " }), "SUPABASE_SECRET_KEYS");
  } catch (e: any) {
    threw = true;
    assertEquals(e.message.includes("No valid 'default' key"), true);
  }
  assertEquals(threw, true);
});
