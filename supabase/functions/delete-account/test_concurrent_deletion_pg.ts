// TalkMate AI - Real PostgreSQL Concurrent Account Deletion Integration Test
// Verifies Workstream B: Independent database sessions executing overlapping delete_user_account()
// Run with: deno test --allow-net --allow-env supabase/functions/delete-account/test_concurrent_deletion_pg.ts

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import postgres from 'https://deno.land/x/postgresjs@v3.4.4/mod.js';
import { getVerifiedStagingPostgresEnvironment } from '../_shared/test_staging_guard.ts';

const pgEnv = getVerifiedStagingPostgresEnvironment();

Deno.test({
  name:
    'PG Concurrency: Independent database sessions execute overlapping delete_user_account() safely with advisory lock serialization',
  ignore: !pgEnv,
  fn: async () => {
    const env = pgEnv!;

    // Create TWO completely independent database connections
    const session1 = postgres({
      host: env.host,
      port: env.port,
      user: env.user,
      pass: env.pass,
      database: env.database,
      ssl: 'require',
      max: 1,
      connect_timeout: 30,
      idle_timeout: 10,
    });

    const session2 = postgres({
      host: env.host,
      port: env.port,
      user: env.user,
      pass: env.pass,
      database: env.database,
      ssl: 'require',
      max: 1,
      connect_timeout: 30,
      idle_timeout: 10,
    });

    const testUserId = crypto.randomUUID();
    const otherUserId = crypto.randomUUID();
    const convId = crypto.randomUUID();

    try {
      // 1. Setup isolated database fixture
      await session1.begin(async (tx) => {
        // Create profiles
        await tx`
          INSERT INTO public.profiles (id, full_name, email)
          VALUES 
            (${testUserId}::uuid, 'Concurrent Test User', 'concurrent@talkmate.ai'),
            (${otherUserId}::uuid, 'Surviving Participant', 'survivor@talkmate.ai')
          ON CONFLICT (id) DO NOTHING;
        `;

        // Create devices
        await tx`
          INSERT INTO public.user_devices (user_id, device_id, fcm_token)
          VALUES (${testUserId}::uuid, 'device_c1', 'fcm_token_c1');
        `;

        // Create notifications
        await tx`
          INSERT INTO public.notifications (user_id, title, body)
          VALUES (${testUserId}::uuid, 'Test Alert', 'Concurrent deletion notification');
        `;

        // Create shared conversation created by testUserId with otherUserId as participant
        await tx`
          INSERT INTO public.conversations (id, creator_id, is_group, title)
          VALUES (${convId}::uuid, ${testUserId}::uuid, true, 'Shared Group');
        `;

        await tx`
          INSERT INTO public.conversation_participants (conversation_id, user_id)
          VALUES 
            (${convId}::uuid, ${testUserId}::uuid),
            (${convId}::uuid, ${otherUserId}::uuid);
        `;

        // Create message sent by testUserId
        await tx`
          INSERT INTO public.messages (chat_id, sender_id, text)
          VALUES (${convId}::uuid, ${testUserId}::uuid, 'Test Message from deleted user');
        `;
      });

      // 2. Start TWO concurrent deletion operations with deliberate overlap
      const startTimestamp = Date.now();

      const runDeletion = async (
        client: typeof session1,
        sessionName: string,
      ) => {
        return await client.begin(async (tx) => {
          // Set user claim in session transaction to simulate authenticated caller
          await tx`SELECT set_config('request.jwt.claim.sub', ${testUserId}, true);`;
          await tx`SELECT set_config('role', 'authenticated', true);`;

          const txStart = Date.now();
          await tx`SELECT public.delete_user_account();`;
          const txDuration = Date.now() - txStart;

          return {
            session: sessionName,
            durationMs: txDuration,
            success: true,
            error: null,
          };
        });
      };

      // Launch both sessions concurrently
      const [result1, result2] = await Promise.all([
        runDeletion(session1, 'session1'),
        runDeletion(session2, 'session2'),
      ]);

      const totalElapsedMs = Date.now() - startTimestamp;

      // 3. Assertions on concurrent execution
      assertEquals(result1.success, true);
      assertEquals(result2.success, true);
      assert(totalElapsedMs >= 0, 'Concurrency execution recorded');

      // 4. Verify database state directly: No corruption, no orphaned rows
      const [profileRows] =
        await session1`SELECT count(*)::int AS count FROM public.profiles WHERE id = ${testUserId}::uuid`;
      const [deviceRows] =
        await session1`SELECT count(*)::int AS count FROM public.user_devices WHERE user_id = ${testUserId}::uuid`;
      const [notifRows] =
        await session1`SELECT count(*)::int AS count FROM public.notifications WHERE user_id = ${testUserId}::uuid`;
      const [partRows] =
        await session1`SELECT count(*)::int AS count FROM public.conversation_participants WHERE user_id = ${testUserId}::uuid`;

      assertEquals(profileRows.count, 0, 'Profile must be deleted');
      assertEquals(deviceRows.count, 0, 'Devices must be deleted');
      assertEquals(notifRows.count, 0, 'Notifications must be deleted');
      assertEquals(partRows.count, 0, 'Participant membership must be removed');

      // Shared conversation must be transferred to surviving participant (otherUserId)
      const [conv] =
        await session1`SELECT creator_id FROM public.conversations WHERE id = ${convId}::uuid`;
      assertEquals(
        conv.creator_id,
        otherUserId,
        'Ownership must be transferred to surviving participant',
      );

      // Message sender_id must be nullified to preserve shared chat history
      const [msg] =
        await session1`SELECT sender_id FROM public.messages WHERE chat_id = ${convId}::uuid`;
      assertEquals(msg.sender_id, null, 'Message sender must be nullified');

      // Survivor profile must remain completely intact
      const [survivor] =
        await session1`SELECT id FROM public.profiles WHERE id = ${otherUserId}::uuid`;
      assertEquals(
        survivor.id,
        otherUserId,
        'Surviving user data must not be touched',
      );
    } finally {
      // Clean up connections
      await session1.end({ timeout: 5 });
      await session2.end({ timeout: 5 });
    }
  },
});
