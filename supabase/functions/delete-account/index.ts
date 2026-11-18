// TalkMate AI - Server-Controlled Complete Account Deletion Edge Function (SEC-02)
// Handles complete account lifecycle deletion:
// 1. Verifies caller's authenticated JWT via Supabase Auth
// 2. Derives target identity strictly from validated token (never trusts client payload)
// 3. Executes transactional database data cleanup via delete_user_account() RPC
// 4. Safely removes user-exclusive storage objects via Storage Admin API
// 5. Deletes Supabase Auth identity via GoTrue Admin API (auth.admin.deleteUser)
// 6. Supports idempotent retries

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.42.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function parseRequiredKey(envVarName: string): string {
  const raw = Deno.env.get(envVarName);
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

interface StorageFileItem {
  name: string;
  id?: string | null;
  metadata?: Record<string, unknown> | null;
}

export async function listAllStorageFiles(
  storageClient: any,
  bucketName: string,
  rootPrefix: string
): Promise<{ files: string[]; error: unknown | null }> {
  const discoveredFilesSet = new Set<string>();
  const visitedFolders = new Set<string>();
  const foldersToTraverse: string[] = [rootPrefix];
  const MAX_DISCOVERED_FILES = 2000;
  const PAGE_SIZE = 100;

  while (foldersToTraverse.length > 0) {
    const currentFolder = foldersToTraverse.shift()!;
    if (visitedFolders.has(currentFolder)) {
      continue;
    }
    visitedFolders.add(currentFolder);

    let offset = 0;
    let hasMore = true;

    while (hasMore) {
      const { data, error } = await storageClient
        .from(bucketName)
        .list(currentFolder, {
          limit: PAGE_SIZE,
          offset,
          sortBy: { column: "name", order: "asc" },
        });

      if (error) {
        return { files: [], error };
      }

      if (!data || data.length === 0) {
        break;
      }

      for (const item of (data as StorageFileItem[])) {
        if (!item.name) continue;

        const fullPath = currentFolder ? `${currentFolder}/${item.name}` : item.name;

        // OFFICIAL SUPABASE STORAGE API SPECIFICATION:
        // In Supabase Storage, folder prefixes returned by list() have id === null or id === undefined.
        // Actual stored objects (files) always have a valid UUID string in item.id.
        // We do NOT use filename extensions or metadata heuristics.
        const isFolder = item.id === null || item.id === undefined;

        if (isFolder) {
          if (!visitedFolders.has(fullPath) && !foldersToTraverse.includes(fullPath)) {
            foldersToTraverse.push(fullPath);
          }
        } else {
          // It's a genuine file object (with extension, without extension, Unicode, spaces, etc.)
          discoveredFilesSet.add(fullPath);

          if (discoveredFilesSet.size > MAX_DISCOVERED_FILES) {
            return {
              files: Array.from(discoveredFilesSet),
              error: new Error(
                `Storage discovery exceeded operational limit of ${MAX_DISCOVERED_FILES} files. Account deletion aborted to prevent partial deletion.`
              ),
            };
          }
        }
      }

      if (data.length < PAGE_SIZE) {
        hasMore = false;
      } else {
        offset += PAGE_SIZE;
      }
    }
  }

  // Sort files deterministically for consistent batching and verification
  const sortedFiles = Array.from(discoveredFilesSet).sort();
  return { files: sortedFiles, error: null };
}

export async function handleDeleteAccount(
  req: Request,
  overrides?: {
    supabaseUrl?: string;
    publishableKey?: string;
    secretKey?: string;
    userClient?: any;
    adminClient?: any;
  }
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseUrl = overrides?.supabaseUrl || Deno.env.get("SUPABASE_URL");
    if (!supabaseUrl || supabaseUrl.trim().length === 0) {
      console.error(JSON.stringify({
        event: "CONFIG_ERROR",
        message: "Missing SUPABASE_URL environment configuration",
        timestamp: new Date().toISOString(),
      }));
      return new Response(
        JSON.stringify({ error: "Internal server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let publishableKey: string;
    let secretKey: string;

    if (overrides?.publishableKey && overrides?.secretKey) {
      publishableKey = overrides.publishableKey;
      secretKey = overrides.secretKey;
    } else {
      try {
        publishableKey = parseRequiredKey("SUPABASE_PUBLISHABLE_KEYS");
        secretKey = parseRequiredKey("SUPABASE_SECRET_KEYS");
      } catch (keyErr) {
        console.error(JSON.stringify({
          event: "CONFIG_ERROR",
          message: keyErr instanceof Error ? keyErr.message : "Key configuration parsing failed",
          timestamp: new Date().toISOString(),
        }));
        return new Response(
          JSON.stringify({ error: "Internal server configuration error" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // 1. Authentication Header Extraction
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Missing or malformed authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Validate user identity using Supabase Auth
    const userClient = overrides?.userClient || createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Invalid or expired session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const authenticatedUserId = user.id;

    // 3. Request body inspection (if client provided an ID, verify it matches token)
    let body: any = {};
    try {
      const text = await req.text();
      if (text && text.trim().length > 0) {
        body = JSON.parse(text);
      }
    } catch (_) {
      // Body is optional; ignoring malformed body
    }

    if (body.targetUserId && body.targetUserId !== authenticatedUserId) {
      return new Response(
        JSON.stringify({ error: "Forbidden: You cannot delete an account that does not belong to you" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Initialize privileged admin client for authorized server-side operations
    const adminClient = overrides?.adminClient || createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false },
    });

    // 5. Execute database data cleanup via delete_user_account()
    // We execute via userClient so auth.uid() is populated as authenticatedUserId
    const { error: rpcError } = await userClient.rpc("delete_user_account");
    if (rpcError) {
      console.error(JSON.stringify({
        event: "ACCOUNT_DELETION_RPC_FAILED",
        userIdHash: authenticatedUserId.substring(0, 8),
        errorCode: rpcError.code,
        message: "RPC delete_user_account failed. Account deletion aborted to prevent partial deletion state.",
      }));
      return new Response(
        JSON.stringify({
          error: "Failed to clean up user database records. Account deletion aborted.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 6. Reliable Storage Cleanup (recursively discover and delete all user-owned objects)
    const userPrefix = `users/${authenticatedUserId}`;
    const { files: pathsToDelete, error: storageListError } = await listAllStorageFiles(
      adminClient.storage,
      "talkmate",
      userPrefix
    );

    if (storageListError) {
      console.error(JSON.stringify({
        event: "ACCOUNT_DELETION_STORAGE_LIST_FAILED",
        userIdHash: authenticatedUserId.substring(0, 8),
        error: storageListError instanceof Error ? storageListError.message : String(storageListError),
        message: "Failed to list user storage objects. Account deletion aborted to prevent partial deletion state.",
      }));
      return new Response(
        JSON.stringify({
          error: "Failed to clean up user storage objects. Account deletion aborted.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (pathsToDelete.length > 0) {
      // Batch remove up to 100 paths at a time per Supabase Storage API limits
      const BATCH_SIZE = 100;
      for (let i = 0; i < pathsToDelete.length; i += BATCH_SIZE) {
        const batch = pathsToDelete.slice(i, i + BATCH_SIZE);
        const { error: removeError } = await adminClient.storage
          .from("talkmate")
          .remove(batch);

        if (removeError) {
          console.error(JSON.stringify({
            event: "ACCOUNT_DELETION_STORAGE_REMOVE_FAILED",
            userIdHash: authenticatedUserId.substring(0, 8),
            error: removeError instanceof Error ? removeError.message : String(removeError),
            batchCount: batch.length,
            message: "Failed to remove user storage objects. Account deletion aborted to prevent partial deletion state.",
          }));
          return new Response(
            JSON.stringify({
              error: "Failed to clean up user storage objects. Account deletion aborted.",
            }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }
    }

    // 7. Delete Auth Identity via GoTrue Admin API
    const { error: authDeleteError } = await adminClient.auth.admin.deleteUser(
      authenticatedUserId
    );

    if (authDeleteError) {
      // If user already deleted, idempotent success
      const msg = authDeleteError.message || "";
      const isAlreadyDeleted =
        (authDeleteError as any).status === 404 ||
        msg.toLowerCase().includes("not found");

      if (!isAlreadyDeleted) {
        console.error(JSON.stringify({
          event: "AUTH_DELETE_FAILURE",
          userIdHash: authenticatedUserId.substring(0, 8),
          message: "Failed to delete user identity from Supabase Auth",
        }));
        return new Response(
          JSON.stringify({ error: "Failed to complete authentication identity deletion" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // 8. Success Response
    return new Response(
      JSON.stringify({
        success: true,
        message: "Account and authentication identity successfully deleted",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error(JSON.stringify({
      event: "SERVER_EXCEPTION",
      message: "Unexpected error during account deletion",
    }));
    return new Response(
      JSON.stringify({ error: "Internal processing error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
}

serve(async (req: Request) => {
  return await handleDeleteAccount(req);
});
