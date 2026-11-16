// TalkMate AI - Real Database Integration Test Suite for Call Record Integrity & RLS
// Tests execute directly against the live Supabase PostgreSQL database.
// Run with: deno test --unsafely-ignore-certificate-errors --allow-net --allow-env supabase/functions/push-handler/test_db_calls_integrity.ts

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

// Helper to run query as an authenticated Supabase user
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

function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    sanitizeOps: false,
    sanitizeResources: false,
    fn,
  });
}

test("Scenario 1: Sender creates a call with a valid receiver", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'video')
      RETURNING id, sender_id, receiver_id, status;
    `;
    assertEquals(call.sender_id, ALICE_ID);
    assertEquals(call.receiver_id, BOB_ID);
    assertEquals(call.status, "ringing");
  });
});

test("Scenario 2: Sender attempts to change receiver_id (BLOCKED)", async () => {
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

test("Scenario 3: Sender attempts to change caller_id (BLOCKED)", async () => {
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
          SET caller_id = ${EVE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call caller/sender identity"
    );
  });
});

test("Scenario 4: Sender attempts to change sender_id (BLOCKED)", async () => {
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
          SET sender_id = ${EVE_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call caller/sender identity"
    );
  });
});

test("Scenario 5: Receiver attempts to change sender_id (BLOCKED)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Now switch to Bob
    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;

    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET sender_id = ${BOB_ID}
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call caller/sender identity"
    );
  });
});

test("Scenario 6: Receiver attempts to change receiver_id (BLOCKED)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Switch to Bob
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

test("Scenario 7: Legitimate call acceptance succeeds (by receiver Bob)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Bob accepts
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

test("Scenario 8: Legitimate call rejection succeeds (by receiver Bob)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Bob rejects
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

test("Scenario 9: Legitimate call termination succeeds (ended status)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Alice ends call
    const [updated] = await tx`
      UPDATE public.calls 
      SET status = 'ended', ended_at = now()
      WHERE id = ${call.id}
      RETURNING status;
    `;
    assertEquals(updated.status, "ended");
  });
});

test("Scenario 10: Legitimate offer, answer, and candidates updates remain functional", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'video')
      RETURNING id;
    `;

    // Alice sets offer
    const offerPayload = { type: "offer", sdp: "v=0..." };
    const [withOffer] = await tx`
      UPDATE public.calls 
      SET offer = ${offerPayload}
      WHERE id = ${call.id}
      RETURNING offer;
    `;
    assertEquals(withOffer.offer.type, "offer");

    // Bob sets answer
    await tx`SELECT set_config('request.jwt.claim.sub', ${BOB_ID}, true)`;
    const answerPayload = { type: "answer", sdp: "v=0..." };
    const [withAnswer] = await tx`
      UPDATE public.calls 
      SET answer = ${answerPayload}
      WHERE id = ${call.id}
      RETURNING answer;
    `;
    assertEquals(withAnswer.answer.type, "answer");
  });
});

test("Scenario 11: Invalid status transitions are rejected (terminal call reopening)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // End call
    await tx`
      UPDATE public.calls 
      SET status = 'ended', ended_at = now()
      WHERE id = ${call.id};
    `;

    // Attacker attempts to reopen ended call back to ringing
    await assertRejects(
      async () => {
        await tx`
          UPDATE public.calls 
          SET status = 'ringing'
          WHERE id = ${call.id};
        `;
      },
      Error,
      "Cannot modify call in terminal status ended"
    );
  });
});

test("Scenario 12: Unrelated user Eve cannot alter a call between Alice and Bob", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Switch to unrelated user Eve
    await tx`SELECT set_config('request.jwt.claim.sub', ${EVE_ID}, true)`;

    // Due to RLS, Eve sees 0 rows to update
    const result = await tx`
      UPDATE public.calls 
      SET status = 'ended'
      WHERE id = ${call.id}
      RETURNING id;
    `;
    assertEquals(result.length, 0); // RLS prevents Eve from updating
  });
});

test("Scenario 13: Caller Alice cannot accept or reject the call (only Bob can)", async () => {
  await asUser(ALICE_ID, async (tx) => {
    const [call] = await tx`
      INSERT INTO public.calls (sender_id, caller_id, receiver_id, callee_id, status, type)
      VALUES (${ALICE_ID}, ${ALICE_ID}, ${BOB_ID}, ${BOB_ID}, 'ringing', 'audio')
      RETURNING id;
    `;

    // Alice attempts to set accepted
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

// Close database connection
test("Cleanup connection", async () => {
  await sql.end();
});
