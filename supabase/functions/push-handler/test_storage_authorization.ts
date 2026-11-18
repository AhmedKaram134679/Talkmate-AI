// TalkMate AI - Real Supabase Storage API Group & User Authorization Suite (SEC-05)
// Verifies Storage RLS, bucket permissions, and member isolation against verified Staging.
// Run with: deno test --allow-net --allow-env supabase/functions/push-handler/test_storage_authorization.ts

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getVerifiedStagingEnvironment, StagingTestEnvironment } from "../_shared/test_staging_guard.ts";

const stagingEnv = getVerifiedStagingEnvironment();

interface TestUser {
  id: string;
  email: string;
  token: string;
}

async function createAndLoginUser(
  env: StagingTestEnvironment,
  label: string,
  userTracker: string[]
): Promise<TestUser> {
  const email = `test_storage_${label}_${Date.now()}_${Math.random().toString(36).substring(7)}@example.com`;
  const password = "StorageTestPassword123!";

  const createRes = await fetch(`${env.supabaseUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      "apikey": env.secretKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: `Storage Test ${label}` },
    }),
  });

  assertEquals(createRes.status, 200, `Failed to create user ${label}`);
  const user = await createRes.json();
  userTracker.push(user.id); // Track immediately for guaranteed cleanup

  const loginRes = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      "apikey": env.publishableKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });

  assertEquals(loginRes.status, 200, `Failed to log in as user ${label}`);
  const loginData = await loginRes.json();

  return {
    id: user.id,
    email,
    token: loginData.access_token,
  };
}

Deno.test({
  name: "SEC-05: Real Supabase Storage API Group & User Authorization Suite",
  ignore: !stagingEnv,
  fn: async () => {
    const env = stagingEnv!;
    const createdUserIds: string[] = [];
    let convId: string = "";
    const groupFileName = "group_avatar.jpg";
    const testFilePayload = new TextEncoder().encode("REAL_STORAGE_OBJECT_CONTENT_SEC05_OK");
    const userFilePayload = new TextEncoder().encode("ALICE_PRIVATE_FILE_DO_NOT_LEAK");

    try {
      // 1. Setup genuine test users with immediate cleanup tracking
      const alice = await createAndLoginUser(env, "Alice", createdUserIds);
      const bob = await createAndLoginUser(env, "Bob", createdUserIds);
      const charlie = await createAndLoginUser(env, "Charlie", createdUserIds);
      const david = await createAndLoginUser(env, "David", createdUserIds);

      // 2. Setup group conversation via PostgREST with Alice (creator), Bob, and David as participants
      const convRes = await fetch(`${env.supabaseUrl}/rest/v1/conversations`, {
        method: "POST",
        headers: {
          "apikey": env.secretKey,
          "Content-Type": "application/json",
          "Prefer": "return=representation",
        },
        body: JSON.stringify({
          creator_id: alice.id,
          is_group: true,
          group_name: "Security Test Group",
        }),
      });
      assertEquals(convRes.status, 201, "Failed to create test conversation via PostgREST");
      const [conv] = await convRes.json();
      convId = conv.id;

      // Add participants
      const partsRes = await fetch(`${env.supabaseUrl}/rest/v1/conversation_participants`, {
        method: "POST",
        headers: {
          "apikey": env.secretKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify([
          { conversation_id: convId, user_id: alice.id },
          { conversation_id: convId, user_id: bob.id },
          { conversation_id: convId, user_id: david.id },
        ]),
      });
      assertEquals(partsRes.status, 201, "Failed to add conversation participants");
      await partsRes.text();

      const groupFilePath = `groups/${convId}/${groupFileName}`;

      // 3. Setup: Alice uploads genuine group avatar object via Storage API
      const uploadRes = await fetch(`${env.supabaseUrl}/storage/v1/object/talkmate/${groupFilePath}`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${alice.token}`,
          "Content-Type": "image/jpeg",
        },
        body: testFilePayload,
      });
      assertEquals(uploadRes.status, 200, "Alice must be able to upload avatar to group she created");
      await uploadRes.text();

      // 4. Scenario 1: Group Member Bob downloads group avatar -> SUCCESS (200)
      const bobGetRes = await fetch(`${env.supabaseUrl}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
        method: "GET",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${bob.token}`,
        },
      });
      assertEquals(bobGetRes.status, 200, "Group member Bob must be allowed to download group avatar");
      const downloadedBytes = await bobGetRes.arrayBuffer();
      assertEquals(new Uint8Array(downloadedBytes), testFilePayload);

      // 5. Scenario 2: Non-member Charlie attempts to download group avatar -> DENIED (400 or 403 or 404)
      const charlieGetRes = await fetch(`${env.supabaseUrl}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
        method: "GET",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${charlie.token}`,
        },
      });
      assert(
        charlieGetRes.status === 400 || charlieGetRes.status === 404 || charlieGetRes.status === 403,
        `Non-member Charlie must be DENIED download: ${charlieGetRes.status}`
      );
      await charlieGetRes.text();

      // Non-member Charlie attempts to list group folder
      const charlieListRes = await fetch(`${env.supabaseUrl}/storage/v1/object/list/talkmate`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${charlie.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          prefix: `groups/${convId}`,
          limit: 10,
        }),
      });
      assertEquals(charlieListRes.status, 200);
      const charlieList = await charlieListRes.json();
      assertEquals(
        Array.isArray(charlieList) ? charlieList.length : 0,
        0,
        "Non-member Charlie must NOT see any objects in group listing"
      );

      // 6. Scenario 3: Former Member David is removed from group -> loses access
      const removeDavid = await fetch(`${env.supabaseUrl}/rest/v1/conversation_participants?conversation_id=eq.${convId}&user_id=eq.${david.id}`, {
        method: "DELETE",
        headers: {
          "apikey": env.secretKey,
        },
      });
      assertEquals(removeDavid.status, 204, "Failed to remove David from participants");
      await removeDavid.text();

      const davidGetAfterRemoval = await fetch(`${env.supabaseUrl}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
        method: "GET",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${david.token}`,
        },
      });
      assert(
        davidGetAfterRemoval.status === 400 || davidGetAfterRemoval.status === 404 || davidGetAfterRemoval.status === 403,
        `Former member David must be DENIED download after removal: ${davidGetAfterRemoval.status}`
      );
      await davidGetAfterRemoval.text();

      // 7. Scenario 4: Unauthorized Upload (Charlie cannot upload into group)
      const charlieUpload = await fetch(`${env.supabaseUrl}/storage/v1/object/talkmate/groups/${convId}/charlie_exploit.jpg`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${charlie.token}`,
          "Content-Type": "image/jpeg",
        },
        body: new Uint8Array([1, 2, 3]),
      });
      assert(
        charlieUpload.status === 400 || charlieUpload.status === 403 || !charlieUpload.ok,
        `Non-member Charlie must be DENIED upload into group: ${charlieUpload.status}`
      );
      await charlieUpload.text();

      // 8. Scenario 5: Unauthorized Deletion (Charlie cannot delete Alice's group avatar)
      const charlieDelete = await fetch(`${env.supabaseUrl}/storage/v1/object/talkmate/${groupFilePath}`, {
        method: "DELETE",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${charlie.token}`,
        },
      });
      await charlieDelete.text();

      // Confirm file still exists for Alice
      const checkStillExists = await fetch(`${env.supabaseUrl}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
        method: "GET",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${alice.token}`,
        },
      });
      assertEquals(checkStillExists.status, 200, "Group avatar must NOT have been deleted by Charlie");
      await checkStillExists.text();

      // 9. Scenario 6: User Private Storage Isolation (users/{userId}/*)
      const alicePrivatePath = `users/${alice.id}/private_doc.txt`;
      const alicePrivateUpload = await fetch(`${env.supabaseUrl}/storage/v1/object/talkmate/${alicePrivatePath}`, {
        method: "POST",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${alice.token}`,
          "Content-Type": "text/plain",
        },
        body: userFilePayload,
      });
      assert(alicePrivateUpload.status === 200 || alicePrivateUpload.status === 201, "Alice uploading to own folder must succeed");
      await alicePrivateUpload.text();

      // Bob attempts to read Alice's private file
      const bobReadAlicePrivate = await fetch(`${env.supabaseUrl}/storage/v1/object/authenticated/talkmate/${alicePrivatePath}`, {
        method: "GET",
        headers: {
          "apikey": env.publishableKey,
          "Authorization": `Bearer ${bob.token}`,
        },
      });
      assert(
        bobReadAlicePrivate.status === 400 || bobReadAlicePrivate.status === 404 || bobReadAlicePrivate.status === 403,
        `Bob must NOT be allowed to read Alice's private file: ${bobReadAlicePrivate.status}`
      );
      await bobReadAlicePrivate.text();
    } finally {
      // Guaranteed cleanup of all created storage objects, conversation records, and test users
      if (convId) {
        try {
          const delStorage = await fetch(`${env.supabaseUrl}/storage/v1/object/talkmate`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              prefixes: [`groups/${convId}`],
            }),
          });
          await delStorage.text();
        } catch (_) {}

        try {
          const delParts = await fetch(`${env.supabaseUrl}/rest/v1/conversation_participants?conversation_id=eq.${convId}`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
            },
          });
          await delParts.text();

          const delConv = await fetch(`${env.supabaseUrl}/rest/v1/conversations?id=eq.${convId}`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
            },
          });
          await delConv.text();
        } catch (_) {}
      }

      // Cleanup user private files and all created users
      for (const userId of createdUserIds) {
        try {
          await fetch(`${env.supabaseUrl}/storage/v1/object/talkmate`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              prefixes: [`users/${userId}`],
            }),
          });
        } catch (_) {}

        try {
          await fetch(`${env.supabaseUrl}/auth/v1/admin/users/${userId}`, {
            method: "DELETE",
            headers: {
              "apikey": env.secretKey,
            },
          });
        } catch (_) {}
      }
    }
  },
});
