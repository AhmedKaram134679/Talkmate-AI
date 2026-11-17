// TalkMate AI - Real Group Storage API Authorization Integration Test Suite (SEC-05)
// Validates end-to-end Storage API permissions with real uploaded files and authenticated sessions:
// - Alice (Group creator / member)
// - Bob (Group member)
// - Charlie (Non-member)
// - David (Former member removed from group)
// 100% HTTPS with strict CA TLS validation (no raw database pooler bypass needed).
// Run with: deno test --no-config --allow-net --allow-env supabase/functions/push-handler/test_storage_authorization.ts

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://icdbbfsjbslzctshxytd.supabase.co";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!ANON_KEY || !SERVICE_ROLE_KEY) {
  throw new Error("SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY must be provided via environment variables.");
}

interface TestUser {
  id: string;
  email: string;
  token: string;
}

async function createAndLoginUser(label: string): Promise<TestUser> {
  const email = `test_storage_${label}_${Date.now()}@example.com`;
  const password = "StorageTestPassword123!";

  const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      "apikey": SERVICE_ROLE_KEY!,
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
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

  const loginRes = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      "apikey": ANON_KEY!,
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

async function deleteUser(id: string) {
  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${id}`, {
      method: "DELETE",
      headers: {
        "apikey": SERVICE_ROLE_KEY!,
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      },
    });
    await res.text();
  } catch (_) {}
}

Deno.test("SEC-05: Real Supabase Storage API Group & User Authorization Suite", async () => {
  // 1. Setup genuine test users
  const alice = await createAndLoginUser("Alice");
  const bob = await createAndLoginUser("Bob");
  const charlie = await createAndLoginUser("Charlie");
  const david = await createAndLoginUser("David");

  let convId: string = "";
  const groupFileName = "group_avatar.jpg";
  const testFilePayload = new TextEncoder().encode("REAL_STORAGE_OBJECT_CONTENT_SEC05_OK");
  const userFilePayload = new TextEncoder().encode("ALICE_PRIVATE_FILE_DO_NOT_LEAK");

  try {
    // 2. Setup group conversation via PostgREST with Alice (creator), Bob, and David as participants
    const convRes = await fetch(`${SUPABASE_URL}/rest/v1/conversations`, {
      method: "POST",
      headers: {
        "apikey": SERVICE_ROLE_KEY!,
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
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
    const partsRes = await fetch(`${SUPABASE_URL}/rest/v1/conversation_participants`, {
      method: "POST",
      headers: {
        "apikey": SERVICE_ROLE_KEY!,
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
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
    const uploadRes = await fetch(`${SUPABASE_URL}/storage/v1/object/talkmate/${groupFilePath}`, {
      method: "POST",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${alice.token}`,
        "Content-Type": "image/jpeg",
      },
      body: testFilePayload,
    });
    assert(uploadRes.status === 200 || uploadRes.status === 201, `Alice must be allowed to upload group avatar: ${uploadRes.status}`);
    await uploadRes.text();

    // 4. Scenario 1: Group Members (Alice and Bob) CAN download and list group avatar
    // Alice downloads:
    const aliceGet = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
      method: "GET",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${alice.token}`,
      },
    });
    assertEquals(aliceGet.status, 200, "Creator Alice must be allowed to download group avatar");
    const aliceBytes = await aliceGet.arrayBuffer();
    assertEquals(aliceBytes.byteLength, testFilePayload.byteLength);

    // Bob (member) downloads:
    const bobGet = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
      method: "GET",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${bob.token}`,
      },
    });
    assertEquals(bobGet.status, 200, "Member Bob must be allowed to download group avatar");
    const bobBytes = await bobGet.arrayBuffer();
    assertEquals(bobBytes.byteLength, testFilePayload.byteLength);

    // 5. Scenario 2: Non-member Charlie CANNOT download or list group avatar
    const charlieGet = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
      method: "GET",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${charlie.token}`,
      },
    });
    // Supabase Storage RLS returns 400 or 404 (Object not found) when policy denies read
    assert(
      charlieGet.status === 400 || charlieGet.status === 404 || charlieGet.status === 403,
      `Non-member Charlie must be DENIED download: ${charlieGet.status}`
    );
    await charlieGet.text();

    // Charlie lists groups/{convId}/*
    const charlieList = await fetch(`${SUPABASE_URL}/storage/v1/object/list/talkmate`, {
      method: "POST",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${charlie.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ prefix: `groups/${convId}` }),
    });
    const charlieListData = await charlieList.json();
    assertEquals(
      Array.isArray(charlieListData) ? charlieListData.length : 0,
      0,
      "Non-member Charlie must NOT see any objects in group listing"
    );

    // 6. Scenario 3: Former Member David is removed from group -> loses access
    const removeDavid = await fetch(`${SUPABASE_URL}/rest/v1/conversation_participants?conversation_id=eq.${convId}&user_id=eq.${david.id}`, {
      method: "DELETE",
      headers: {
        "apikey": SERVICE_ROLE_KEY!,
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      },
    });
    assertEquals(removeDavid.status, 204, "Failed to remove David from participants");
    await removeDavid.text();

    const davidGetAfterRemoval = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
      method: "GET",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${david.token}`,
      },
    });
    assert(
      davidGetAfterRemoval.status === 400 || davidGetAfterRemoval.status === 404 || davidGetAfterRemoval.status === 403,
      `Former member David must be DENIED download after removal: ${davidGetAfterRemoval.status}`
    );
    await davidGetAfterRemoval.text();

    // 7. Scenario 4: Unauthorized Upload (Charlie cannot upload into group)
    const charlieUpload = await fetch(`${SUPABASE_URL}/storage/v1/object/talkmate/groups/${convId}/charlie_exploit.jpg`, {
      method: "POST",
      headers: {
        "apikey": ANON_KEY!,
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
    const charlieDelete = await fetch(`${SUPABASE_URL}/storage/v1/object/talkmate/${groupFilePath}`, {
      method: "DELETE",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${charlie.token}`,
      },
    });
    await charlieDelete.text();

    // Confirm file still exists for Alice
    const checkStillExists = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/talkmate/${groupFilePath}`, {
      method: "GET",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${alice.token}`,
      },
    });
    assertEquals(checkStillExists.status, 200, "Group avatar must NOT have been deleted by Charlie");
    await checkStillExists.text();

    // 9. Scenario 6: User Private Storage Isolation (users/{userId}/*)
    const alicePrivatePath = `users/${alice.id}/private_doc.txt`;
    const alicePrivateUpload = await fetch(`${SUPABASE_URL}/storage/v1/object/talkmate/${alicePrivatePath}`, {
      method: "POST",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${alice.token}`,
        "Content-Type": "text/plain",
      },
      body: userFilePayload,
    });
    assert(alicePrivateUpload.status === 200 || alicePrivateUpload.status === 201, "Alice uploading to own folder must succeed");
    await alicePrivateUpload.text();

    // Bob attempts to read Alice's private file
    const bobReadAlicePrivate = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/talkmate/${alicePrivatePath}`, {
      method: "GET",
      headers: {
        "apikey": ANON_KEY!,
        "Authorization": `Bearer ${bob.token}`,
      },
    });
    assert(
      bobReadAlicePrivate.status === 400 || bobReadAlicePrivate.status === 404 || bobReadAlicePrivate.status === 403,
      `Bob must NOT be allowed to read Alice's private file: ${bobReadAlicePrivate.status}`
    );
    await bobReadAlicePrivate.text();
  } finally {
    // Cleanup storage objects and data using service role
    if (convId) {
      try {
        const delStorage = await fetch(`${SUPABASE_URL}/storage/v1/object/talkmate`, {
          method: "DELETE",
          headers: {
            "apikey": SERVICE_ROLE_KEY!,
            "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            prefixes: [`groups/${convId}`, `users/${alice.id}`],
          }),
        });
        await delStorage.text();
      } catch (_) {}

      try {
        const delParts = await fetch(`${SUPABASE_URL}/rest/v1/conversation_participants?conversation_id=eq.${convId}`, {
          method: "DELETE",
          headers: {
            "apikey": SERVICE_ROLE_KEY!,
            "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
          },
        });
        await delParts.text();

        const delConv = await fetch(`${SUPABASE_URL}/rest/v1/conversations?id=eq.${convId}`, {
          method: "DELETE",
          headers: {
            "apikey": SERVICE_ROLE_KEY!,
            "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
          },
        });
        await delConv.text();
      } catch (_) {}
    }

    await deleteUser(alice.id);
    await deleteUser(bob.id);
    await deleteUser(charlie.id);
    await deleteUser(david.id);
  }
});
