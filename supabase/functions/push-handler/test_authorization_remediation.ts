// TalkMate AI - Persistent Security Regression Test Suite
// Validates Call Lifecycle Authorization, Canonical Room ID, and Private Room Recipient Isolation
// Run via: deno test --allow-none supabase/functions/push-handler/test_authorization_remediation.ts

import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

interface CallRow {
  id: string;
  sender_id: string;
  receiver_id: string;
  status: string;
  type?: string;
  is_video?: boolean;
}

interface RoomRow {
  id: string;
  name: string;
  created_by: string;
  is_private: boolean;
  allowed_users: string[];
}

interface MessageRow {
  id: string;
  sender_id: string;
  chat_id: string;
  text: string;
  type: string;
}

interface ProfileRow {
  id: string;
  username: string;
  display_name: string;
}

interface DeviceRow {
  user_id: string;
  device_id: string;
  fcm_token: string;
  is_active: boolean;
}

// In-memory isolated database
class MockSupabaseDB {
  calls = new Map<string, CallRow>();
  rooms = new Map<string, RoomRow>();
  messages = new Map<string, MessageRow>();
  profiles = new Map<string, ProfileRow>();
  devices: DeviceRow[] = [];
  sentFcmMessages: any[] = [];

  resetFcmLogs() {
    this.sentFcmMessages = [];
  }
}

// Test harness implementing the exact logic of push-handler/index.ts
class PushHandlerHarness {
  db: MockSupabaseDB;
  serviceRoleKey = "mock_service_role_secret_key_12345";

  constructor(db: MockSupabaseDB) {
    this.db = db;
  }

  async handleRequest(
    authHeader: string | null,
    rawPayload: any
  ): Promise<{ status: number; body: any }> {
    // 1. Authentication
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return { status: 401, body: { error: "Missing or invalid authorization header" } };
    }

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    let callerRole: string | null = null;
    let callerUserId: string | null = null;

    if (token === this.serviceRoleKey) {
      callerRole = "service_role";
    } else if (token.startsWith("user_jwt_")) {
      callerRole = "authenticated";
      callerUserId = token.replace("user_jwt_", "");
    } else {
      return { status: 401, body: { error: "Unauthorized: Invalid JWT token" } };
    }

    let payload = { ...rawPayload };

    // STAGE R: UNWRAP ENVELOPE (From SQL Triggers)
    if (payload.record) {
      const type = payload.type || "message";
      payload = {
        ...payload.record,
        content_type: payload.record.type || (type === "reaction" ? "reaction" : "text"),
        message_id: payload.record.id || payload.record.message_id,
        sender_id: payload.record.user_id || payload.record.sender_id,
      };
    }

    const {
      chat_id,
      sender_id,
      message_id,
      type: payloadType,
    } = payload;

    // Caller Authorization check: If not service_role, strictly verify against trusted database records
    if (callerRole !== "service_role") {
      if (payloadType === "call_ringing" || payloadType === "INCOMING_CALL" || payload.receiver_id) {
        const callId = payload.call_id || message_id;
        if (!callId) {
          return { status: 403, body: { error: "Forbidden: Missing call record identifier" } };
        }

        const callRecord = this.db.calls.get(callId);
        if (!callRecord) {
          return { status: 403, body: { error: "Forbidden: Referenced call record not found" } };
        }

        // 1. Call Lifecycle Authorization: Only 'ringing' calls permit incoming call notifications
        if (callRecord.status !== "ringing") {
          return { status: 403, body: { error: `Forbidden: Call is not in ringing state (status: ${callRecord.status})` } };
        }

        const dbSenderId = callRecord.sender_id;
        const dbReceiverId = callRecord.receiver_id;

        if (callerUserId !== dbSenderId) {
          return { status: 403, body: { error: "Forbidden: Caller does not match call sender" } };
        }

        const canonicalCallId = String(callRecord.id);
        payload.call_id = canonicalCallId;
        payload.message_id = canonicalCallId;
        payload.sender_id = dbSenderId;
        payload.receiver_id = dbReceiverId;
      } else if (payloadType === "room_created") {
        const roomId = payload.room_id || payload.id;
        if (!roomId) {
          return { status: 403, body: { error: "Forbidden: Missing room identifier" } };
        }

        const roomRecord = this.db.rooms.get(roomId);
        if (!roomRecord) {
          return { status: 403, body: { error: "Forbidden: Referenced room record not found" } };
        }

        if (callerUserId !== roomRecord.created_by) {
          return { status: 403, body: { error: "Forbidden: Caller does not match room creator" } };
        }

        const canonicalRoomId = String(roomRecord.id);
        payload.id = canonicalRoomId;
        payload.room_id = canonicalRoomId;
        payload.created_by = roomRecord.created_by;
        if (roomRecord.name) payload.name = roomRecord.name;
        payload.is_private = roomRecord.is_private === true;
        payload.allowed_users = Array.isArray(roomRecord.allowed_users) ? roomRecord.allowed_users : [];
      } else {
        // Message payload
        if (!message_id) {
          return { status: 403, body: { error: "Forbidden: Missing message record identifier" } };
        }

        const messageRecord = this.db.messages.get(message_id);
        if (!messageRecord) {
          return { status: 403, body: { error: "Forbidden: Referenced message record not found" } };
        }

        if (callerUserId !== messageRecord.sender_id) {
          return { status: 403, body: { error: "Forbidden: Caller does not match message sender" } };
        }

        payload.sender_id = messageRecord.sender_id;
        payload.chat_id = messageRecord.chat_id;
        if (messageRecord.text) payload.text_content = messageRecord.text;
        if (messageRecord.type) payload.content_type = messageRecord.type;
      }
    }

    // STAGE R: SPECIALIZED CALL HANDLING
    if (payloadType === "call_ringing" || payloadType === "INCOMING_CALL" || payload.receiver_id) {
      const callId = payload.call_id || message_id;
      if (!callId) return { status: 400, body: { error: "Missing call identifier" } };

      const callRecord = this.db.calls.get(callId);
      if (!callRecord) return { status: 404, body: { error: "Referenced call record not found" } };

      if (callRecord.status !== "ringing") {
        return { status: 403, body: { error: `Call is not in ringing state (status: ${callRecord.status})` } };
      }

      const canonicalCallId = String(callRecord.id);
      const finalSenderId = callRecord.sender_id;
      const receiverId = callRecord.receiver_id;
      const isVideo = callRecord.is_video === true || callRecord.type === "video";

      const senderProfile = this.db.profiles.get(finalSenderId);
      const callerName = senderProfile?.display_name || "TalkMate User";

      const devices = this.db.devices.filter((d) => d.user_id === receiverId && d.is_active);
      if (devices.length === 0) return { status: 200, body: { message: "No devices for receiver" } };

      const results = devices.map((d) => {
        const msg = {
          token: d.fcm_token,
          data: {
            type: "INCOMING_CALL",
            call_id: canonicalCallId,
            sender_id: String(finalSenderId),
            is_video: String(isVideo),
            caller_name: callerName,
          },
        };
        this.db.sentFcmMessages.push(msg);
        return { device: d.device_id, status: "sent" };
      });

      return { status: 200, body: { results } };
    }

    // STAGE R: ROOM CREATION HANDLING
    if (payloadType === "room_created") {
      const targetRoomId = payload.room_id || payload.id;
      if (!targetRoomId) return { status: 400, body: { error: "Missing room metadata: id" } };

      const roomRecord = this.db.rooms.get(targetRoomId);
      if (!roomRecord) return { status: 404, body: { error: "Room record not found" } };

      const canonicalRoomId = String(roomRecord.id);
      const creatorId = roomRecord.created_by;
      const roomName = roomRecord.name || payload.name || "A Room";
      const isPrivate = roomRecord.is_private === true;
      const allowedUsers = Array.isArray(roomRecord.allowed_users) ? roomRecord.allowed_users : [];

      if (!creatorId) return { status: 400, body: { error: "Missing created_by in room record" } };

      const creatorProfile = this.db.profiles.get(creatorId);
      const creatorName = creatorProfile?.display_name || "A user";

      let recipientIds: string[] = [];
      if (isPrivate) {
        // ONLY users explicitly listed in allowed_users, strictly excluding creator
        recipientIds = allowedUsers.filter((uid: string) => uid && uid !== creatorId);
      } else {
        // Public rooms: active users excluding creator
        recipientIds = Array.from(this.db.profiles.keys()).filter((uid) => uid !== creatorId);
      }

      if (recipientIds.length === 0) return { status: 200, body: { message: "No recipients for room" } };

      const devices = this.db.devices.filter((d) => recipientIds.includes(d.user_id) && d.is_active);
      if (devices.length === 0) return { status: 200, body: { message: "No devices found" } };

      const results = devices.map((d) => {
        const msg = {
          token: d.fcm_token,
          notification: {
            title: "New Room Active",
            body: `${creatorName} created room: ${roomName}`,
          },
          data: {
            type: "room_created",
            room_id: canonicalRoomId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        };
        this.db.sentFcmMessages.push(msg);
        return { device: d.device_id, status: "sent" };
      });

      return { status: 200, body: { results } };
    }

    // Message Handling
    const effectiveChatId = payload.chat_id || chat_id;
    const effectiveSenderId = payload.sender_id || sender_id;

    if (!effectiveChatId || !effectiveSenderId) {
      return { status: 400, body: { error: "Missing chat_id or sender_id" } };
    }

    return { status: 200, body: { status: "message_processed", sender: effectiveSenderId, chat: effectiveChatId } };
  }
}

// Test fixtures setup
function setupTestDatabase(): MockSupabaseDB {
  const db = new MockSupabaseDB();

  // Profiles
  db.profiles.set("user_alice", { id: "user_alice", username: "alice", display_name: "Alice" });
  db.profiles.set("user_bob", { id: "user_bob", username: "bob", display_name: "Bob" });
  db.profiles.set("user_charlie", { id: "user_charlie", username: "charlie", display_name: "Charlie" });
  db.profiles.set("user_eve", { id: "user_eve", username: "eve", display_name: "Eve" });

  // Devices
  db.devices.push({ user_id: "user_bob", device_id: "dev_bob_1", fcm_token: "token_bob", is_active: true });
  db.devices.push({ user_id: "user_charlie", device_id: "dev_charlie_1", fcm_token: "token_charlie", is_active: true });
  db.devices.push({ user_id: "user_eve", device_id: "dev_eve_1", fcm_token: "token_eve", is_active: true });
  db.devices.push({ user_id: "user_alice", device_id: "dev_alice_1", fcm_token: "token_alice", is_active: true });

  // Calls
  db.calls.set("call_ringing_1", {
    id: "call_ringing_1",
    sender_id: "user_alice",
    receiver_id: "user_bob",
    status: "ringing",
    type: "video",
    is_video: true,
  });
  db.calls.set("call_ended_2", {
    id: "call_ended_2",
    sender_id: "user_alice",
    receiver_id: "user_bob",
    status: "ended",
  });
  db.calls.set("call_rejected_3", {
    id: "call_rejected_3",
    sender_id: "user_alice",
    receiver_id: "user_bob",
    status: "rejected",
  });
  db.calls.set("call_missed_4", {
    id: "call_missed_4",
    sender_id: "user_alice",
    receiver_id: "user_bob",
    status: "missed",
  });

  // Rooms
  db.rooms.set("room_pub_100", {
    id: "room_pub_100",
    name: "Public Hangout",
    created_by: "user_alice",
    is_private: false,
    allowed_users: [],
  });
  db.rooms.set("room_priv_200", {
    id: "room_priv_200",
    name: "Confidential Executive Room",
    created_by: "user_alice",
    is_private: true,
    allowed_users: ["user_alice", "user_bob"], // Only Bob is authorized; Charlie and Eve are NOT
  });

  // Messages
  db.messages.set("msg_real_1", {
    id: "msg_real_1",
    sender_id: "user_alice",
    chat_id: "chat_alice_bob",
    text: "Hello Bob",
    type: "text",
  });

  return db;
}

// ==========================================
// 1. CALL LIFECYCLE AUTHORIZATION TESTS
// ==========================================

Deno.test("Call: Valid ringing call returns 200 and dispatches FCM to DB receiver", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_ringing_1",
    sender_id: "user_alice",
    receiver_id: "user_bob",
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages.length, 1);
  assertEquals(db.sentFcmMessages[0].token, "token_bob");
  assertEquals(db.sentFcmMessages[0].data.call_id, "call_ringing_1");
  assertEquals(db.sentFcmMessages[0].data.sender_id, "user_alice");
});

Deno.test("Call: Ended call is rejected with 403 and sends zero FCM", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_ended_2",
  });

  assertEquals(res.status, 403);
  assertEquals(db.sentFcmMessages.length, 0);
});

Deno.test("Call: Rejected call is rejected with 403 and sends zero FCM", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_rejected_3",
  });

  assertEquals(res.status, 403);
  assertEquals(db.sentFcmMessages.length, 0);
});

Deno.test("Call: Cancelled/missed call is rejected with 403 and sends zero FCM", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_missed_4",
  });

  assertEquals(res.status, 403);
  assertEquals(db.sentFcmMessages.length, 0);
});

Deno.test("Call: Nonexistent call is rejected with 403 and sends zero FCM", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_does_not_exist",
  });

  assertEquals(res.status, 403);
  assertEquals(db.sentFcmMessages.length, 0);
});

Deno.test("Call: Caller mismatch (attacker Eve triggers for Alice's call) is rejected with 403", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_eve", {
    type: "call_ringing",
    call_id: "call_ringing_1",
  });

  assertEquals(res.status, 403);
  assertEquals(db.sentFcmMessages.length, 0);
});

Deno.test("Call: Forged receiver_id in payload is strictly overwritten by DB record", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  // Alice is caller, but passes forged receiver_id = user_eve
  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_ringing_1",
    receiver_id: "user_eve", // Forged receiver
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages.length, 1);
  // FCM must be delivered to BOB (DB receiver), NEVER to Eve
  assertEquals(db.sentFcmMessages[0].token, "token_bob");
  assertNotEquals(db.sentFcmMessages[0].token, "token_eve");
});

Deno.test("Call: Replayed notification after call status transitions to ended fails with 403", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  // First call while ringing: succeeds
  const res1 = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_ringing_1",
  });
  assertEquals(res1.status, 200);
  assertEquals(db.sentFcmMessages.length, 1);

  // State transitions to ended in DB
  const call = db.calls.get("call_ringing_1")!;
  call.status = "ended";
  db.resetFcmLogs();

  // Second replayed call: rejected!
  const res2 = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "call_ringing",
    call_id: "call_ringing_1",
  });
  assertEquals(res2.status, 403);
  assertEquals(db.sentFcmMessages.length, 0);
});

// ==========================================
// 2. CANONICAL ROOM ID TESTS
// ==========================================

Deno.test("Room: Accepts 'room_id' format and sets canonical room_id in FCM data", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    room_id: "room_pub_100", // using room_id key
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages.length > 0, true);
  for (const msg of db.sentFcmMessages) {
    assertEquals(msg.data.room_id, "room_pub_100");
    assertNotEquals(msg.data.room_id, "undefined");
  }
});

Deno.test("Room: Accepts 'id' format and sets same canonical room_id in FCM data", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    id: "room_pub_100", // using id key
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages.length > 0, true);
  for (const msg of db.sentFcmMessages) {
    assertEquals(msg.data.room_id, "room_pub_100");
  }
});

Deno.test("Room: Forged caller-supplied room name is overwritten by DB record", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    room_id: "room_pub_100",
    name: "Forged Phishing Name", // caller attempts to spoof room title
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages[0].notification.body.includes("Public Hangout"), true);
  assertEquals(db.sentFcmMessages[0].notification.body.includes("Forged Phishing Name"), false);
});

// ==========================================
// 3. PRIVATE ROOM RECIPIENT ISOLATION TESTS
// ==========================================

Deno.test("Private Room: Creator Alice does NOT receive notification for her own room", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    room_id: "room_priv_200",
  });

  assertEquals(res.status, 200);
  const deliveredTokens = db.sentFcmMessages.map((m) => m.token);
  assertEquals(deliveredTokens.includes("token_alice"), false);
});

Deno.test("Private Room: Authorized user Bob receives notification", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    room_id: "room_priv_200",
  });

  assertEquals(res.status, 200);
  const deliveredTokens = db.sentFcmMessages.map((m) => m.token);
  assertEquals(deliveredTokens.includes("token_bob"), true);
});

Deno.test("Private Room: Unauthorized users (Charlie, Eve) NEVER receive notification", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    room_id: "room_priv_200",
  });

  assertEquals(res.status, 200);
  const deliveredTokens = db.sentFcmMessages.map((m) => m.token);
  assertEquals(deliveredTokens.includes("token_charlie"), false);
  assertEquals(deliveredTokens.includes("token_eve"), false);
});

Deno.test("Public Room: All eligible non-creator users receive notification", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "room_created",
    room_id: "room_pub_100",
  });

  assertEquals(res.status, 200);
  const deliveredTokens = db.sentFcmMessages.map((m) => m.token);
  assertEquals(deliveredTokens.includes("token_bob"), true);
  assertEquals(deliveredTokens.includes("token_charlie"), true);
  assertEquals(deliveredTokens.includes("token_eve"), true);
  assertEquals(deliveredTokens.includes("token_alice"), false); // Creator still excluded
});

// ==========================================
// 4. SERVICE ROLE TRIGGER PATH TESTS
// ==========================================

Deno.test("Service Role: Trigger-generated call_ringing payload succeeds", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest(`Bearer ${harness.serviceRoleKey}`, {
    type: "call_ringing",
    call_id: "call_ringing_1",
    sender_id: "user_alice",
    receiver_id: "user_bob",
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages.length, 1);
  assertEquals(db.sentFcmMessages[0].token, "token_bob");
});

Deno.test("Service Role: Trigger-generated room_created payload succeeds with canonical ID", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest(`Bearer ${harness.serviceRoleKey}`, {
    type: "room_created",
    id: "room_priv_200",
    name: "Confidential Executive Room",
    created_by: "user_alice",
  });

  assertEquals(res.status, 200);
  assertEquals(db.sentFcmMessages.length, 1);
  assertEquals(db.sentFcmMessages[0].token, "token_bob");
  assertEquals(db.sentFcmMessages[0].data.room_id, "room_priv_200");
});

// ==========================================
// 5. MESSAGE RECORD AUTHORIZATION TESTS
// ==========================================

Deno.test("Message: Valid sender with real DB record succeeds", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "message",
    message_id: "msg_real_1",
    chat_id: "chat_alice_bob",
    sender_id: "user_alice",
  });

  assertEquals(res.status, 200);
  assertEquals(res.body.status, "message_processed");
  assertEquals(res.body.sender, "user_alice");
});

Deno.test("Message: Attacker Eve forging Alice's message is rejected with 403", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_eve", {
    type: "message",
    message_id: "msg_real_1",
    sender_id: "user_alice",
  });

  assertEquals(res.status, 403);
});

Deno.test("Message: Nonexistent message ID is rejected with 403", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "message",
    message_id: "msg_nonexistent_999",
    sender_id: "user_alice",
  });

  assertEquals(res.status, 403);
});

Deno.test("Message: Spoofed chat_id in payload is strictly overwritten by DB record", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest("Bearer user_jwt_user_alice", {
    type: "message",
    message_id: "msg_real_1",
    chat_id: "spoofed_unrelated_chat", // Alice passes fake chat
    sender_id: "user_alice",
  });

  assertEquals(res.status, 200);
  // Verified chat must be the authentic DB chat
  assertEquals(res.body.chat, "chat_alice_bob");
  assertNotEquals(res.body.chat, "spoofed_unrelated_chat");
});

Deno.test("Message: Database trigger (service_role) unwrap envelope succeeds", async () => {
  const db = setupTestDatabase();
  const harness = new PushHandlerHarness(db);

  const res = await harness.handleRequest(`Bearer ${harness.serviceRoleKey}`, {
    record: {
      id: "msg_trig_row",
      chat_id: "chat_system_announcements",
      sender_id: "user_alice",
      type: "text",
      text: "System broadcast message",
      created_at: new Date().toISOString(),
    },
  });

  assertEquals(res.status, 200);
  assertEquals(res.body.status, "message_processed");
  assertEquals(res.body.chat, "chat_system_announcements");
});
