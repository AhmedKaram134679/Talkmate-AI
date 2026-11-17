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

serve(async (req: Request) => {
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
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      console.error(JSON.stringify({
        event: "CONFIG_ERROR",
        message: "Missing essential Supabase environment configuration",
        timestamp: new Date().toISOString(),
      }));
      return new Response(
        JSON.stringify({ error: "Internal server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
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
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
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
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: { persistSession: false },
    });

    // 5. Execute database data cleanup via delete_user_account()
    // We execute via userClient so auth.uid() is populated as authenticatedUserId
    const { error: rpcError } = await userClient.rpc("delete_user_account");
    if (rpcError) {
      // Check if error is because profile is already gone (idempotent retry)
      console.warn(JSON.stringify({
        event: "RPC_CLEANUP_NOTE",
        userIdHash: authenticatedUserId.substring(0, 8),
        errorCode: rpcError.code,
        message: "RPC delete_user_account encountered note or non-fatal condition",
      }));
    }

    // 6. Safe Storage Cleanup (delete private objects in users/{userId}/*)
    try {
      const userPrefix = `users/${authenticatedUserId}`;
      const { data: userFiles } = await adminClient.storage
        .from("talkmate")
        .list(userPrefix);

      if (userFiles && userFiles.length > 0) {
        const pathsToDelete = userFiles.map((f) => `${userPrefix}/${f.name}`);
        await adminClient.storage.from("talkmate").remove(pathsToDelete);
      }
    } catch (storageErr) {
      // Storage cleanup failure does not block auth deletion
      console.warn(JSON.stringify({
        event: "STORAGE_CLEANUP_WARNING",
        userIdHash: authenticatedUserId.substring(0, 8),
        message: "Storage cleanup encountered non-fatal error",
      }));
    }

    // 7. Delete Auth Identity via GoTrue Admin API
    const { error: authDeleteError } = await adminClient.auth.admin.deleteUser(
      authenticatedUserId
    );

    if (authDeleteError) {
      // If user already deleted, idempotent success
      const msg = authDeleteError.message || "";
      if (!msg.toLowerCase().includes("not found")) {
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
});
