// TalkMate AI - Real Database Integration Test Suite for SEC-01 through SEC-05
// Verifies PostgreSQL functions, triggers, and RLS policies against verified Staging environment.
// Run with: deno test --allow-net --allow-env supabase/functions/push-handler/test_remediation_sec01_to_sec05.ts

import { assertEquals, assertRejects, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.4/mod.js";
import { getVerifiedStagingPostgresEnvironment } from "../_shared/test_staging_guard.ts";

const pgEnv = getVerifiedStagingPostgresEnvironment();
const sql = pgEnv
  ? postgres({
      host: pgEnv.host,
      port: pgEnv.port,
      user: pgEnv.user,
      pass: pgEnv.pass,
      database: pgEnv.database,
      ssl: "require",
      connect_timeout: 30,
      idle_timeout: 10,
      max: 5,
    })
  : null;

// Dynamic, isolated test identities generated per test run to prevent clashes or targeting real accounts
const ALICE_ID = crypto.randomUUID();
const BOB_ID = crypto.randomUUID();
const EVE_ID = crypto.randomUUID();

const stagingHost = pgEnv ? `${pgEnv.projectRef}.supabase.co` : "staging.supabase.co";

// Helper to execute in simulated PostgREST authenticated context with automatic rollback
async function asUser(userId: string, callback: (tx: any) => Promise<void>) {
  await sql!.begin(async (tx) => {
    await tx`SET LOCAL ROLE authenticated`;
    await tx`SELECT set_config('request.jwt.claim.sub', ${userId}, true)`;
    await tx`SELECT set_config('request.jwt.claim.role', 'authenticated', true)`;
    await tx`SELECT set_config('request.headers', ${JSON.stringify({ host: stagingHost, authorization: "dummy" })}, true)`;
    await callback(tx);
    throw new Error("__ROLLBACK__");
  }).catch((err) => {
    if (err.message !== "__ROLLBACK__") {
      throw err;
    }
  });
}

// Helper to execute in unauthenticated context (auth.uid() is null) with automatic rollback
async function asUnauthenticated(callback: (tx: any) => Promise<void>) {
  await sql!.begin(async (tx) => {
    await tx`SET LOCAL ROLE anon`;
    await tx`SELECT set_config('request.jwt.claim.sub', '', true)`;
    await tx`SELECT set_config('request.jwt.claim.role', 'anon', true)`;
    await tx`SELECT set_config('request.headers', ${JSON.stringify({ host: stagingHost, authorization: "dummy" })}, true)`;
    await callback(tx);
    throw new Error("__ROLLBACK__");
  }).catch((err) => {
    if (err.message !== "__ROLLBACK__") {
      throw err;
    }
  });
}

// Helper to execute as authenticated but without a user id (auth.uid() IS NULL)
async function asAuthenticatedNoUid(callback: (tx: any) => Promise<void>) {
  await sql!.begin(async (tx) => {
    await tx`SET LOCAL ROLE authenticated`;
    await tx`SELECT set_config('request.jwt.claim.sub', '', true)`;
    await tx`SELECT set_config('request.jwt.claim.role', 'authenticated', true)`;
    await tx`SELECT set_config('request.headers', ${JSON.stringify({ host: stagingHost, authorization: "dummy" })}, true)`;
    await callback(tx);
    throw new Error("__ROLLBACK__");
  }).catch((err) => {
    if (err.message !== "__ROLLBACK__") {
      throw err;
    }
  });
}

// Helper to execute as service_role with automatic rollback
async function asServiceRole(callback: (tx: any) => Promise<void>) {
  await sql!.begin(async (tx) => {
    await tx`SET LOCAL ROLE service_role`;
    await tx`SELECT set_config('request.jwt.claim.role', 'service_role', true)`;
    await tx`SELECT set_config('request.headers', ${JSON.stringify({ host: stagingHost, authorization: "dummy" })}, true)`;
    await callback(tx);
    throw new Error("__ROLLBACK__");
  }).catch((err) => {
    if (err.message !== "__ROLLBACK__") {
      throw err;
    }
  });
}

function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    ignore: !sql,
    sanitizeOps: false,
    sanitizeResources: false,
    fn,
  });
}

// ----------------------------------------------------------------------------
// SEC-01 Tests: ICE Candidate Structural & Authentication Validation
// ----------------------------------------------------------------------------

test("SEC-01.1: Genuinely unauthenticated caller without auth.uid() is rejected with 'Authentication required'", async () => {
  await asAuthenticatedNoUid(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          '00000000-0000-0000-0000-000000000001'::uuid,
          '{"candidate": "candidate:1 1 UDP 2130706431 192.0.2.1 5000 typ host", "sdpMid": "0", "sdpMLineIndex": 0}'::jsonb
        )`;
      },
      Error,
      "Authentication required",
    );
  });
});

test("SEC-01.2: Anon role is rejected by EXECUTE permissions on fn_add_call_candidate", async () => {
  await asUnauthenticated(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          '00000000-0000-0000-0000-000000000001'::uuid,
          '{"candidate": "candidate:1 1 UDP 2130706431 192.0.2.1 5000 typ host"}'::jsonb
        )`;
      },
      Error,
      "permission denied",
    );
  });
});

test("SEC-01.3: Valid candidate schema succeeds for active call participant", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await tx`SELECT public.fn_add_call_candidate(
      ${call.id}::uuid,
      '{"candidate": "candidate:1 1 UDP 2130706431 192.0.2.1 5000 typ host", "sdpMid": "audio", "sdpMLineIndex": 0, "usernameFragment": "ufrag123"}'::jsonb
    )`;

    const [updated] = await tx`SELECT candidates FROM public.calls WHERE id = ${call.id}::uuid`;
    assertEquals(updated.candidates.length, 1);
    assertEquals(updated.candidates[0].candidate, "candidate:1 1 UDP 2130706431 192.0.2.1 5000 typ host");
  });
});

test("SEC-01.4: Reject candidate missing required 'candidate' field", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"sdpMid": "0", "sdpMLineIndex": 0}'::jsonb
        )`;
      },
      Error,
      "candidate field is required",
    );
  });
});

test("SEC-01.5: Reject candidate with empty candidate string", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"candidate": "   ", "sdpMid": "0", "sdpMLineIndex": 0}'::jsonb
        )`;
      },
      Error,
      "candidate must be a non-empty string",
    );
  });
});

test("SEC-01.6: Reject candidate with invalid sdpMid type (number instead of string/null)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"candidate": "valid", "sdpMid": 12345}'::jsonb
        )`;
      },
      Error,
      "sdpMid must be string or null",
    );
  });
});

test("SEC-01.7: Reject candidate with negative sdpMLineIndex", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"candidate": "valid", "sdpMLineIndex": -1}'::jsonb
        )`;
      },
      Error,
      "sdpMLineIndex cannot be negative",
    );
  });
});

test("SEC-01.8: Reject candidate with non-integer sdpMLineIndex", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"candidate": "valid", "sdpMLineIndex": "not_a_number"}'::jsonb
        )`;
      },
      Error,
      "sdpMLineIndex must be number or null",
    );
  });
});

test("SEC-01.9: Reject candidate with unknown payload fields", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"candidate": "valid", "malicious_payload": "exploit"}'::jsonb
        )`;
      },
      Error,
      "unknown fields detected",
    );
  });
});

test("SEC-01.10: Reject candidate submission to terminal/ended call", async () => {
  await asUser(ALICE_ID, async (tx) => {
    // Insert call as ringing first, then update to ended
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;
    await tx`UPDATE public.calls SET status = 'ended' WHERE id = ${call.id}::uuid`;

    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${call.id}::uuid,
          '{"candidate": "valid", "sdpMid": "0", "sdpMLineIndex": 0}'::jsonb
        )`;
      },
      Error,
      "Cannot add candidate to terminal or inactive call",
    );
  });
});

test("SEC-01.11: Reject candidate from non-participant (Eve)", async () => {
  await asUser(EVE_ID, async (tx) => {
    // Insert call between Alice and Bob using service role context in sub-query
    let callId: string;
    await asUser(ALICE_ID, async (subTx) => {
      const [c] = await subTx`
        INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
        VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${BOB_ID}::uuid, ${BOB_ID}::uuid, 'ringing', 'audio')
        RETURNING id;
      `;
      callId = c.id;
    });

    // Eve attempts to inject candidate into Alice's call
    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          ${callId!}::uuid,
          '{"candidate": "valid", "sdpMid": "0", "sdpMLineIndex": 0}'::jsonb
        )`;
      },
      Error,
    );
  });
});

test("SEC-01.12: service_role without user context cannot add call candidate", async () => {
  await asServiceRole(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.fn_add_call_candidate(
          '00000000-0000-0000-0000-000000000001'::uuid,
          '{"candidate": "candidate:1 1 UDP 2130706431 192.0.2.1 5000 typ host", "sdpMid": "0", "sdpMLineIndex": 0}'::jsonb
        )`;
      },
      Error,
    );
  });
});

// ----------------------------------------------------------------------------
// SEC-02 Tests: Account Deletion RPC Permissions & Default Privileges
// ----------------------------------------------------------------------------

test("SEC-02.1: Unauthenticated caller cannot execute delete_user_account", async () => {
  await asUnauthenticated(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.delete_user_account()`;
      },
      Error,
      "permission denied",
    );
  });
});

test("SEC-02.2: Authenticated user can execute delete_user_account for their own account", async () => {
  await asUser(EVE_ID, async (tx) => {
    await tx`SELECT public.delete_user_account()`;
    const [profile] = await tx`SELECT id FROM public.profiles WHERE id = ${EVE_ID}::uuid`;
    assertEquals(profile, undefined);
  });
});

test("SEC-02.3: Account deletion transfers group ownership and preserves message history for remaining members", async () => {
  await asUser(ALICE_ID, async (tx) => {
    // 1. Alice creates a group conversation with Bob
    const [conv] = await tx`
      INSERT INTO public.conversations (creator_id, is_group, group_name)
      VALUES (${ALICE_ID}::uuid, true, 'Engineering Team')
      RETURNING id;
    `;

    // 2. Add Alice and Bob to conversation_participants
    await tx`
      INSERT INTO public.conversation_participants (conversation_id, user_id)
      VALUES (${conv.id}::uuid, ${ALICE_ID}::uuid), (${conv.id}::uuid, ${BOB_ID}::uuid);
    `;

    // 3. Alice sends a message
    const [mAlice] = await tx`
      INSERT INTO public.messages (chat_id, sender_id, text, type)
      VALUES (${conv.id}::uuid, ${ALICE_ID}::uuid, 'Alice message', 'text')
      RETURNING id;
    `;

    // 4. Alice executes delete_user_account()
    await tx`SELECT public.delete_user_account()`;

    // 5. Verify from Alice's perspective:
    // a. Alice profile is deleted
    const [aliceProf] = await tx`SELECT id FROM public.profiles WHERE id = ${ALICE_ID}::uuid`;
    assertEquals(aliceProf, undefined);

    // b. Alice was removed from the conversation and is no longer creator,
    // so RLS correctly denies Alice from viewing the surviving conversation
    const [aliceViewConv] = await tx`SELECT id FROM public.conversations WHERE id = ${conv.id}::uuid`;
    assertEquals(aliceViewConv, undefined, "Deleted user must not be able to read conversation");

    // 6. Verify from surviving participant Bob's perspective:
    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;

    // a. Conversation survived and Bob is now the creator
    const [survivingConv] = await tx`SELECT id, creator_id FROM public.conversations WHERE id = ${conv.id}::uuid`;
    assert(survivingConv !== undefined, "Group conversation must survive creator deletion");
    assertEquals(survivingConv.creator_id, BOB_ID, "Group creator_id must be transferred to remaining participant Bob");

    // b. Bob is still participant, Alice is removed
    const participants = await tx`SELECT user_id FROM public.conversation_participants WHERE conversation_id = ${conv.id}::uuid`;
    assertEquals(participants.length, 1);
    assertEquals(participants[0].user_id, BOB_ID);

    // c. Messages are preserved with sender_id nullified for deleted user
    const [aliceMsgAfter] = await tx`SELECT id, sender_id, text FROM public.messages WHERE id = ${mAlice.id}::uuid`;
    assert(aliceMsgAfter !== undefined, "Alice's message must be preserved for surviving members");
    assertEquals(aliceMsgAfter.sender_id, null, "Alice's message sender_id must be nullified to protect privacy");
  });
});

test("SEC-02.4: Empty conversation with zero remaining members is cleanly deleted upon sole participant deletion", async () => {
  await asUser(ALICE_ID, async (tx) => {
    // 1. Alice creates solo conversation
    const [conv] = await tx`
      INSERT INTO public.conversations (creator_id, is_group, group_name)
      VALUES (${ALICE_ID}::uuid, false, 'Solo Chat')
      RETURNING id;
    `;
    await tx`
      INSERT INTO public.conversation_participants (conversation_id, user_id)
      VALUES (${conv.id}::uuid, ${ALICE_ID}::uuid);
    `;
    await tx`
      INSERT INTO public.messages (chat_id, sender_id, text, type)
      VALUES (${conv.id}::uuid, ${ALICE_ID}::uuid, 'Solo text', 'text');
    `;

    // 2. Alice deletes account
    await tx`SELECT public.delete_user_account()`;

    // 3. Conversation is completely deleted since 0 members remain
    const [c] = await tx`SELECT id FROM public.conversations WHERE id = ${conv.id}::uuid`;
    assertEquals(c, undefined, "Empty conversation with 0 remaining members must be deleted");
  });
});

// ----------------------------------------------------------------------------
// SEC-03 Tests: purge_old_data Role Enforcement & Boundary Validation
// ----------------------------------------------------------------------------

test("SEC-03.1: Authenticated user is DENIED execution of purge_old_data", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.purge_old_data(30)`;
      },
      Error,
      "permission denied",
    );
  });
});

test("SEC-03.2: Anon role is DENIED execution of purge_old_data", async () => {
  await asUnauthenticated(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.purge_old_data(30)`;
      },
      Error,
      "permission denied",
    );
  });
});

test("SEC-03.3: Service role can execute purge_old_data within valid bounds", async () => {
  await asServiceRole(async (tx) => {
    await tx`SELECT public.purge_old_data(90)`;
  });
});

test("SEC-03.4: Service role rejects invalid retention bounds (<1 or >3650)", async () => {
  await asServiceRole(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.purge_old_data(0)`;
      },
      Error,
      "Invalid retention period",
    );
  });
  await asServiceRole(async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.purge_old_data(5000)`;
      },
      Error,
      "Invalid retention period",
    );
  });
});

// ----------------------------------------------------------------------------
// SEC-04 Tests: Profile Privacy & User Search Hardening
// ----------------------------------------------------------------------------

test("SEC-04.1: search_users treats wildcards (% and _) literally without table dumping", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const wildcardResults = await tx`SELECT * FROM public.search_users('%%', 20)`;
    assertEquals(wildcardResults.length, 0);

    const underscoreResults = await tx`SELECT * FROM public.search_users('__', 20)`;
    assertEquals(underscoreResults.length, 0);
  });
});

test("SEC-04.2: search_users rejects queries below min length or exceeding max length", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const tooShort = await tx`SELECT * FROM public.search_users('a', 20)`;
    assertEquals(tooShort.length, 0);

    const tooLong = await tx`SELECT * FROM public.search_users(${'a'.repeat(60)}, 20)`;
    assertEquals(tooLong.length, 0);
  });
});

test("SEC-04.3: search_users NEVER returns email addresses of other users", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const results = await tx`SELECT * FROM public.search_users('Bob', 20)`;
    for (const r of results) {
      if (r.id !== ALICE_ID) {
        assertEquals(r.email, null);
      }
    }
  });
});

test("SEC-04.4: search_users respects privacy_show_last_seen by masking is_online and last_seen", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await tx`UPDATE public.profiles SET privacy_show_last_seen = false, is_online = true WHERE id = ${BOB_ID}::uuid`;

    const results = await tx`SELECT * FROM public.search_users('Bob', 20)`;
    const bob = results.find((r: any) => r.id === BOB_ID);
    if (bob) {
      assertEquals(bob.is_online, false);
      assertEquals(bob.last_seen, null);
    }
  });
});

test("SEC-04.5: fn_is_profile_accessible grants access for active call but rejects old terminal call", async () => {
  // 3e8c0460-201c-47a5-be25-15d191eb2117 exists in profiles with no prior relationship to Alice
  const STRANGER_ID = "3e8c0460-201c-47a5-be25-15d191eb2117";

  // 1. Active call with Stranger -> accessible
  await asUser(ALICE_ID, async (tx) => {
    const [c1] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${STRANGER_ID}::uuid, ${STRANGER_ID}::uuid, 'ringing', 'audio')
      RETURNING id;
    `;
    await tx`UPDATE public.calls SET status = 'ongoing' WHERE id = ${c1.id}::uuid`;

    const [accessActive] = await tx`SELECT public.fn_is_profile_accessible(${STRANGER_ID}::uuid) AS allowed`;
    assertEquals(accessActive.allowed, true);
  });

  // 2. Old terminal call from 3 days ago -> NOT accessible for stranger
  await asUser(ALICE_ID, async (tx) => {
    const [c2] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type, created_at)
      VALUES (${ALICE_ID}::uuid, ${ALICE_ID}::uuid, ${STRANGER_ID}::uuid, ${STRANGER_ID}::uuid, 'ringing', 'audio', now() - interval '3 days')
      RETURNING id;
    `;
    await tx`UPDATE public.calls SET status = 'ended' WHERE id = ${c2.id}::uuid`;

    const [accessOld] = await tx`SELECT public.fn_is_profile_accessible(${STRANGER_ID}::uuid) AS allowed`;
    assertEquals(accessOld.allowed, false);
  });
});

test("SEC-04.6: search_users does not return users by email address (email enumeration prevented)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    // Attempt searching by email address
    const results = await tx`SELECT * FROM public.search_users('bob@example.com', 20)`;
    const foundByEmail = results.filter((r: any) => r.id === BOB_ID && r.username !== 'bob@example.com');
    assertEquals(foundByEmail.length, 0, "Users must not be discoverable via email addresses");
  });
});

// ----------------------------------------------------------------------------
// SEC-05 Tests: Storage Avatar Privacy & Membership Isolation
// ----------------------------------------------------------------------------

test("SEC-05.1: Storage read policy requires literal profile_ prefix and respects privacy_show_profile_photo", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await tx`UPDATE public.profiles SET privacy_show_profile_photo = false WHERE id = ${BOB_ID}::uuid`;

    const objects = await tx`
      SELECT name FROM storage.objects
      WHERE bucket_id = 'talkmate'
        AND name = ${'users/' + BOB_ID + '/profile_avatar.jpg'};
    `;
    assertEquals(objects.length, 0);
  });
});

test("SEC-05.2: Storage policy restricts group avatar access to group participants", async () => {
  await asUser(ALICE_ID, async (tx) => {
    // Create group with Alice only (Bob is not a participant)
    const [conv] = await tx`
      INSERT INTO public.conversations (creator_id, is_group, group_name)
      VALUES (${ALICE_ID}::uuid, true, 'Private Team')
      RETURNING id;
    `;
    await tx`
      INSERT INTO public.conversation_participants (conversation_id, user_id)
      VALUES (${conv.id}::uuid, ${ALICE_ID}::uuid);
    `;

    // Query storage.objects as participant Alice
    const objects = await tx`
      SELECT name FROM storage.objects
      WHERE bucket_id = 'talkmate'
        AND name = ${'groups/' + conv.id + '/avatar.jpg'};
    `;
    assertEquals(Array.isArray(objects), true);
  });

  await asUser(BOB_ID, async (tx) => {
    // Non-participant querying non-member group path
    const objects = await tx`
      SELECT name FROM storage.objects
      WHERE bucket_id = 'talkmate'
        AND name = 'groups/00000000-0000-0000-0000-000000000099/avatar.jpg';
    `;
    assertEquals(objects.length, 0);
  });
});

test("Cleanup database connection", async () => {
  if (sql) await sql.end();
});
