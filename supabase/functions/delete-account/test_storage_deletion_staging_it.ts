// TalkMate AI - Real Supabase Storage Deletion Staging Integration Test
// Verifies Workstream A against verified Staging environment:
// 1. Uploads real test objects to Staging 'talkmate' bucket under users/${userId}
// 2. Executes complete account deletion
// 3. Verifies that all storage objects are completely removed and Auth user is deleted
// Run with: deno test --allow-net --allow-env supabase/functions/delete-account/test_storage_deletion_staging_it.ts

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.42.0';
import { getVerifiedStagingEnvironment } from '../_shared/test_staging_guard.ts';
import { handleDeleteAccount } from './index.ts';

const stagingEnv = getVerifiedStagingEnvironment();

Deno.test({
  name:
    'Storage Staging IT: Real Supabase Storage user folder objects are completely removed upon account deletion',
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const adminClient = createClient(env.supabaseUrl, env.secretKey, {
      auth: { persistSession: false },
    });

    const tempEmail = `staging_storage_${Date.now()}_${
      Math.random().toString(36).substring(7)
    }@talkmate.ai`;
    const tempPassword = 'Password123!Secure';
    let createdUserId: string | null = null;

    try {
      // 1. Create test user via admin API
      const { data: userData, error: userCreateErr } = await adminClient.auth
        .admin.createUser({
          email: tempEmail,
          password: tempPassword,
          email_confirm: true,
          user_metadata: { full_name: 'Storage Staging Test' },
        });

      assertEquals(userCreateErr, null);
      assert(userData.user?.id);
      createdUserId = userData.user.id;

      // 2. Sign in as test user to obtain authentic user JWT
      const userClient = createClient(env.supabaseUrl, env.publishableKey, {
        auth: { persistSession: false },
      });
      const { data: sessionData, error: signInErr } = await userClient.auth
        .signInWithPassword({
          email: tempEmail,
          password: tempPassword,
        });

      assertEquals(signInErr, null);
      assert(sessionData.session?.access_token);
      const userJwt = sessionData.session.access_token;

      // 3. Upload real test files to Staging Storage bucket 'talkmate'
      const testFilePaths = [
        `users/${createdUserId}/profile_avatar.jpg`,
        `users/${createdUserId}/audio/voice_note_1.m4a`,
        `users/${createdUserId}/audio/voice_note_2.m4a`,
      ];

      for (const filePath of testFilePaths) {
        const dummyContent = new Uint8Array([1, 2, 3, 4, 5]);
        const { error: uploadErr } = await adminClient.storage
          .from('talkmate')
          .upload(filePath, dummyContent, {
            contentType: 'application/octet-stream',
          });
        assertEquals(uploadErr, null, `Upload of ${filePath} must succeed`);
      }

      // 4. Trigger account deletion via handleDeleteAccount
      const req = new Request(
        `${env.supabaseUrl}/functions/v1/delete-account`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${userJwt}`,
            'apikey': env.publishableKey,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({}),
        },
      );

      const res = await handleDeleteAccount(req, {
        supabaseUrl: env.supabaseUrl,
        publishableKey: env.publishableKey,
        secretKey: env.secretKey,
      });

      assertEquals(res.status, 200, 'Deletion must return 200 OK');
      const data = await res.json();
      assertEquals(data.success, true);

      // 5. Verify real Storage bucket: No user files remain
      const { data: remainingFiles, error: listErr } = await adminClient.storage
        .from('talkmate')
        .list(`users/${createdUserId}`);

      assertEquals(listErr, null);
      assertEquals(
        remainingFiles?.length || 0,
        0,
        'All user files in Staging Storage must be removed',
      );

      // 6. Verify Auth: User identity no longer exists in GoTrue
      const { data: authCheck, error: authCheckErr } = await adminClient.auth
        .admin.getUserById(createdUserId);
      assert(
        authCheckErr !== null || authCheck.user === null,
        'Auth identity must be deleted from Supabase Auth',
      );
      createdUserId = null; // Cleaned up
    } finally {
      // Emergency cleanup if test failed halfway
      if (createdUserId) {
        try {
          await adminClient.auth.admin.deleteUser(createdUserId);
        } catch (_) {}
      }
    }
  },
});
