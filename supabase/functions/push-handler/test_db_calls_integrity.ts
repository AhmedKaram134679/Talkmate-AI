// TalkMate AI - Comprehensive Real Database Integration Test Suite for Call Record Integrity & RLS
// Tests execute directly against the live Supabase PostgreSQL database.
// Run with: deno test --no-config --unsafely-ignore-certificate-errors --allow-net --allow-env --allow-run supabase/functions/push-handler/test_db_calls_integrity.ts

import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.4/mod.js";

async function getCredentials() {
  if (Deno.env.get("PGPASSWORD")) {
    return {
      host: Deno.env.get("PGHOST") || "aws-1-eu-central-1.pooler.supabase.com",
      port: Number(Deno.env.get("PGPORT") || 5432),
      user: Deno.env.get("PGUSER") || "cli_login_postgres.icdbbfsjbslzctshxytd",
      pass: Deno.env.get("PGPASSWORD")!,
      database: Deno.env.get("PGDATABASE") || "postgres",
    };
  }

  // Obtain dynamically via supabase db dump --dry-run
  const cmd = new Deno.Command("supabase", {
    args: ["db", "dump", "--dry-run"],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await cmd.output();
  const text = new TextDecoder().decode(output.stdout);

  const hostMatch = text.match(/export PGHOST="([^"]+)"/);
  const portMatch = text.match(/export PGPORT="([^"]+)"/);
  const userMatch = text.match(/export PGUSER="([^"]+)"/);
  const passMatch = text.match(/export PGPASSWORD="([^"]+)"/);
  const dbMatch = text.match(/export PGDATABASE="([^"]+)"/);

  if (!passMatch || !userMatch) {
    throw new Error("Could not extract pooler credentials from supabase db dump --dry-run");
  }

  return {
    host: hostMatch ? hostMatch[1] : "aws-1-eu-central-1.pooler.supabase.com",
    port: portMatch ? Number(portMatch[1]) : 5432,
    user: userMatch[1],
    pass: passMatch[1],
    database: dbMatch ? dbMatch[1] : "postgres",
  };
}

const creds = await getCredentials();
const sql = postgres({
  host: creds.host,
  port: creds.port,
  user: creds.user,
  pass: creds.pass,
  database: creds.database,
  ssl: { rejectUnauthorized: false },
});

// Real UUIDs existing in auth.users
const ALICE_ID = "20f672ea-ebc9-49d1-9a8a-acd4fa703b7c";
const BOB_ID = "4043be4d-3312-4fac-a0db-3b1502a0d572";
const EVE_ID = "2ae1af25-46ff-417d-b5a0-449bbbc0c1c5";
const CHARLIE_ID = "33333333-3333-3333-3333-333333333333";

// Helper to run query as an authenticated Supabase user with automatic rollback
async function asUser(userId: string, callback: (tx: any) => Promise<void>) {
  await sql.begin(async (tx) => {
    await tx`SET LOCAL ROLE authenticated`;
    await tx`SELECT set_config('request.jwt.claim.sub', ${userId}, true)`;
    await tx`SELECT set_config('request.jwt.claim.role', 'authenticated', true)`;
    await tx`SELECT set_config('request.headers', '{"host": "icdbbfsjbslzctshxytd.supabase.co", "authorization": "dummy"}', true)`;
    await callback(tx);
    throw new Error("__ROLLBACK__"); // Deterministic rollback so test records never persist
  }).catch((err) => {
    if (err.message !== "__ROLLBACK__") {
      throw err;
    }
  });
}

// Helper to run query as service_role
async function asServiceRole(callback: (tx: any) => Promise<void>) {
  await sql.begin(async (tx) => {
    await tx`SET LOCAL ROLE service_role`;
    await tx`SELECT set_config('request.jwt.claim.role', 'service_role', true)`;
    await tx`SELECT set_config('request.headers', '{"host": "icdbbfsjbslzctshxytd.supabase.co", "authorization": "dummy"}', true)`;
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
    sanitizeOps: false,
    sanitizeResources: false,
    fn,
  });
}

// ============================================================================
// Group 1: INSERT Identity Validation & Legacy Compatibility
// ============================================================================

test("1. INSERT: Both sender identifiers NULL is rejected", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`
          INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
          VALUES (NULL, NULL, ${BOB_ID}, ${BOB_ID}, 'ringing', 'video');
        `;
      },
      Error
    );
  });
});

test("2. INSERT: Mismatched sender identifiers (sender_id != caller_id) is rejected", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`
          INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
          VALUES (${ALICE_ID}, ${EVE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'video');
        `;
      },
      Error
    );
  });
});

test("3. INSERT: Mismatched receiver identifiers (receiver_id != callee_id) is rejected", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`
          INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
          VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${EVE_ID}, 'ringing', 'video');
        `;
      },
      Error
    );
  });
});

test("4. INSERT: Valid legacy INSERT using only caller_id succeeds and synchronizes", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (caller_id, receiver_id, status, type)
      VALUES (${ALICE_ID}, ${BOB_ID}, 'ringing', 'video')
      RETURNING id, sender_id, caller_id, receiver_id, callee_id, status;
    `;
    assertEquals(call.caller_id, ALICE_ID);
    assertEquals(call.sender_id, ALICE_ID);
    assertEquals(call.receiver_id, BOB_ID);
    assertEquals(call.callee_id, BOB_ID);
    assertEquals(call.status, "ringing");
  });
});

test("5. INSERT: Valid legacy INSERT using only sender_id succeeds and synchronizes", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, receiver_id, status, type)
      VALUES (${ALICE_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id, sender_id, caller_id, receiver_id, callee_id, status;
    `;
    assertEquals(call.sender_id, ALICE_ID);
    assertEquals(call.caller_id, ALICE_ID);
    assertEquals(call.receiver_id, BOB_ID);
    assertEquals(call.callee_id, BOB_ID);
  });
});

test("6. INSERT: Valid legacy INSERT using only callee_id succeeds and synchronizes", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id, sender_id, caller_id, receiver_id, callee_id, status;
    `;
    assertEquals(call.receiver_id, BOB_ID);
    assertEquals(call.callee_id, BOB_ID);
  });
});

test("7. INSERT: Invalid initial status (e.g. ongoing, accepted, ended) is rejected", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`
          INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
          VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ongoing', 'audio');
        `;
      },
      Error
    );
  });

  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`
          INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
          VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'accepted', 'audio');
        `;
      },
      Error
    );
  });

  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`
          INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
          VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ended', 'audio');
        `;
      },
      Error
    );
  });
});

// ============================================================================
// Group 2: Immutability of Participant Identifiers & Metadata
// ============================================================================

test("8. UPDATE: Sender attempting to change receiver_id is BLOCKED", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET receiver_id = ${CHARLIE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call receiver/callee identity"
    );
  });
});

test("9. UPDATE: Sender attempting to change caller_id or sender_id is BLOCKED", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET caller_id = ${CHARLIE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call caller/sender identity"
    );
  });

  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET sender_id = ${CHARLIE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call caller/sender identity"
    );
  });
});

test("10. UPDATE: Receiver attempting to change sender_id or receiver_id is BLOCKED", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET sender_id = ${CHARLIE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call caller/sender identity"
    );
  });

  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET receiver_id = ${CHARLIE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call receiver/callee identity"
    );
  });
});

// ============================================================================
// Group 3: Call State Machine, Reopening Prevention & Participant Authorization
// ============================================================================

test("11. STATE: Legitimate call acceptance by receiver Bob succeeds", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Switch to receiver Bob
    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;

    const [updated] = await tx`
      UPDATE public.calls 
      SET status = 'accepted'
      WHERE id = ${call.id}
      RETURNING status;
    `;
    assertEquals(updated.status, "accepted");
  });
});

test("12. STATE: Legitimate call rejection by receiver Bob succeeds", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Switch to receiver Bob
    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;

    const [updated] = await tx`
      UPDATE public.calls 
      SET status = 'rejected', ended_at = now()
      WHERE id = ${call.id}
      RETURNING status;
    `;
    assertEquals(updated.status, "rejected");
  });
});

test("13. STATE: Caller Alice attempting to accept call is BLOCKED", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET status = 'accepted'
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Only call receiver can accepted the call"
    );
  });
});

test("14. STATE: Caller Alice attempting to reject call is BLOCKED (Caller terminates with ended)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Alice is caller; only receiver Bob can reject
    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET status = 'rejected'
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Only call receiver can rejected the call"
    );
  });
});

test("15. STATE: Legitimate caller cancellation (ringing -> ended) succeeds", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Alice legitimately cancels ringing call
    const [updated] = await tx`
      UPDATE public.calls 
      SET status = 'ended', ended_at = now()
      WHERE id = ${call.id}
      RETURNING status;
    `;
    assertEquals(updated.status, "ended");
  });
});

test("16. STATE: Legitimate direct transition from ringing to ongoing succeeds", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    const [updated] = await tx`
      UPDATE public.calls 
      SET status = 'ongoing', started_at = now()
      WHERE id = ${call.id}
      RETURNING status;
    `;
    assertEquals(updated.status, "ongoing");
  });
});

test("17. STATE: Unknown or unsupported target statuses are rejected", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET status = 'invented_fake_status'
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Invalid target call status"
    );
  });
});

test("18. STATE: Every terminal status reopening attempt is strictly BLOCKED", async () => {
  const terminalStatuses = ['ended', 'rejected', 'missed', 'failed'];

  for (const termStatus of terminalStatuses) {
    // 1. Reopening attempt to ringing
    await asUser(ALICE_ID, async (tx) => {
      const [call] = await tx`
        INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
        VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
        RETURNING id;
      `;

      if (termStatus === 'rejected') {
        await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;
        await tx`UPDATE public.calls SET status = 'rejected' WHERE id = ${call.id}`;
      } else {
        await tx`UPDATE public.calls SET status = ${termStatus} WHERE id = ${call.id}`;
      }

      await assertRejects(
        async () => {
          await tx`UPDATE public.calls SET status = 'ringing' WHERE id = ${call.id}`;
        },
        Error,
        `Cannot modify call in terminal status ${termStatus}`
      );
    });

    // 2. Reopening attempt to ongoing
    await asUser(ALICE_ID, async (tx) => {
      const [call] = await tx`
        INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
        VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
        RETURNING id;
      `;

      if (termStatus === 'rejected') {
        await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;
        await tx`UPDATE public.calls SET status = 'rejected' WHERE id = ${call.id}`;
      } else {
        await tx`UPDATE public.calls SET status = ${termStatus} WHERE id = ${call.id}`;
      }

      await assertRejects(
        async () => {
          await tx`UPDATE public.calls SET status = 'ongoing' WHERE id = ${call.id}`;
        },
        Error,
        `Cannot modify call in terminal status ${termStatus}`
      );
    });
  }
});

// ============================================================================
// Group 4: WebRTC Signaling, ICE Candidates & RLS Isolation
// ============================================================================

test("19. SIGNALING: Legitimate offer, answer, and ICE candidates update properly", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // 1. Caller sets offer
    const offerPayload = { type: "offer", sdp: "v=0\r\no=alice..." };
    const [withOffer] = await tx`
      UPDATE public.calls 
      SET offer = ${offerPayload}
      WHERE id = ${call.id}
      RETURNING offer;
    `;
    assertEquals(withOffer.offer.type, "offer");

    // 2. Callee sets answer
    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;
    const answerPayload = { type: "answer", sdp: "v=0\r\no=bob..." };
    const [withAnswer] = await tx`
      UPDATE public.calls 
      SET answer = ${answerPayload}
      WHERE id = ${call.id}
      RETURNING answer;
    `;
    assertEquals(withAnswer.answer.type, "answer");

    // 3. ICE Candidate update
    const candidatePayload = [{ candidate: "candidate:1...", sdpMid: "0" }];
    const [withCandidates] = await tx`
      UPDATE public.calls 
      SET candidates = ${candidatePayload}
      WHERE id = ${call.id}
      RETURNING candidates;
    `;
    assertEquals(withCandidates.candidates.length, 1);
  });
});

test("20. SIGNALING: Signaling update on call with unknown status is strictly BLOCKED", async () => {
  // If a legacy row existed with unknown status 'calling_unknown'
  await asServiceRole(async (tx) => {
    // service_role simulates a legacy anomaly
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Force legacy status directly as service role
    await tx`UPDATE public.calls SET status = 'legacy_unknown' WHERE id = ${call.id}`;

    // Now switch to Alice and attempt signaling-only update (status unmodified)
    await tx`SET LOCAL ROLE authenticated`;
    await tx`SELECT set_config('request.jwt.claim.sub', ${ALICE_ID}, true)`;
    await tx`SELECT set_config('request.jwt.claim.role', 'authenticated', true)`;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET offer = '{"type": "offer"}'::jsonb
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Invalid existing call status: legacy_unknown"
    );
  });
});

test("21. ISOLATION: Unrelated user Eve cannot view or alter call between Alice and Bob", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Switch to outsider Eve
    await tx`SELECT set_config('request.jwt.claim.sub', ${EVE_ID}, true)`;

    // RLS SELECT blocks Eve
    const rows = await tx`SELECT id FROM public.calls WHERE id = ${call.id}`;
    assertEquals(rows.length, 0);

    // RLS UPDATE blocks Eve
    const result = await tx`
      UPDATE public.calls 
      SET status = 'ended'
      WHERE id = ${call.id}
      RETURNING id;
    `;
    assertEquals(result.length, 0);
  });
});

// ============================================================================
// Group 5: Trusted Service Role Operations & Trigger Privilege Defense
// ============================================================================

test("22. TRUSTED SERVICE: service_role can perform automated maintenance transitions", async () => {
  await asServiceRole(async (tx) => {
    // service_role creates call
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'video')
      RETURNING id, status;
    `;
    assertEquals(call.status, "ringing");

    // service_role can clean up stale calls directly to ended
    const [ended] = await tx`
      UPDATE public.calls 
      SET status = 'ended', ended_at = now()
      WHERE id = ${call.id}
      RETURNING status;
    `;
    assertEquals(ended.status, "ended");
  });
});

test("23. SECURITY: Authenticated user cannot spoof role or reach service_role bypass", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    await tx`UPDATE public.calls SET status = 'ended' WHERE id = ${call.id}`;

    // Attacker attempts set_config('role', 'service_role', true)
    await tx`SELECT set_config('role', 'service_role', true)`;

    // Attempt to reopen call exploiting spoofed setting
    await assertRejects(
      async () => {
        await tx`UPDATE public.calls SET status = 'ringing' WHERE id = ${call.id}`;
      },
      Error,
      "Cannot modify call in terminal status ended"
    );
  });
});

test("24. SECURITY: Authenticated user cannot execute fn_protect_calls_integrity directly", async () => {
  await asUser(ALICE_ID, async (tx) => {
    await assertRejects(
      async () => {
        await tx`SELECT public.fn_protect_calls_integrity();`;
      },
      Error,
      "permission denied for function fn_protect_calls_integrity"
    );
  });
});

// Close database connection
test("Cleanup connection", async () => {
  await sql.end();
});
