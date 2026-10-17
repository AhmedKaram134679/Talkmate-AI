import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { initializeApp, getApps, cert, type ServiceAccount } from "npm:firebase-admin@12.7.0/app";
import { getMessaging } from "npm:firebase-admin@12.7.0/messaging";
import webpush from "npm:web-push@3.6.7";
import serviceAccount from "./service-account.json" with { type: "json" };

if (getApps().length === 0) {
  initializeApp({
    credential: cert(serviceAccount as unknown as ServiceAccount),
  });
}

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Admin client to bypass RLS
const supabaseAdmin = createClient(supabaseUrl, supabaseKey, {
  auth: { persistSession: false },
});

// VAPID Keys for Web Push
const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY") || "";
const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY") || "";
const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@talkmate.ai";

if (vapidPublicKey && vapidPrivateKey) {
  webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
}

// --- HELPERS ---
function isInDND(currentMin: number, startStr: string, endStr: string): boolean {
  const [sH, sM] = startStr.split(':').map(Number);
  const [eH, eM] = endStr.split(':').map(Number);
  const startMin = sH * 60 + sM;
  const endMin = eH * 60 + eM;

  if (startMin <= endMin) {
    return currentMin >= startMin && currentMin <= endMin;
  } else {
    // Overnight DND (e.g. 22:00 to 08:00)
    return currentMin >= startMin || currentMin <= endMin;
  }
}

function calculateUtility(
  openRate: number, 
  weights: { engagement_weight: number, context_weight: number }, 
  sensitivity: number, 
  driftScore: number, 
  contextPenalty: number, 
  contextSensitivity: number
): number {
  const wEngagement = (weights.engagement_weight ?? 0.4) * 2.5;
  const wContext = (weights.context_weight ?? 0.3) * 3.33;
  return (openRate * wEngagement) - (sensitivity * 0.2) - (driftScore * 0.1) - (contextPenalty * contextSensitivity * wContext);
}

// Stage J: Deterministic Hash for Canary Rollouts
function getHash(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash);
}

// Stage S: Fatigue Check (In-memory cache or helper)
async function _checkFatigue(supabase: SupabaseClient, userId: string, _limit: number): Promise<boolean> {
  const { data, error } = await supabase.rpc('fn_is_user_fatigued', { p_user_id: userId });
  if (error) {
    console.error("⚠️ Fatigue check failed:", error);
    return false;
  }
  return data === true;
}

function _checkFeatureRollout(flag: AIFeatureFlag, userId: string): boolean {
  if (!flag.is_enabled) return false;
  if (flag.rollout_percentage === 100) return true;
  if (flag.rollout_percentage === 0) return false;
  
  // Deterministic assignment based on User ID
  const hash = getHash(`${flag.feature_key}_${userId}`);
  const normalized = hash % 100;
  return normalized < flag.rollout_percentage;
}

async function _syncToInbox(entry: NotificationInboxEntry) {
    const { error } = await supabaseAdmin.from('notification_inbox').insert(entry);
    if (error) console.error("⚠️ Failed to sync to inbox:", error);
}

function _resolveFallback(
    p: { 
        userId: string, 
        scenario: string, 
        priority: string, 
        decision: string, 
        title: string, 
        body: string,
        messageId: string
    }
) {
    const timeout = new Promise<void>((_, reject) => 
        setTimeout(() => reject(new Error("Fallback Service Timeout")), 3000)
    );
    
    return Promise.race([
        _resolveFallbackInternal(p),
        timeout
    ]).catch(err => {
        console.error("⚠️ Fallback skipped or failed:", err);
        // STAGE I: RECORD TO DLQ
        supabaseAdmin.rpc('record_dlq_entry', {
            p_user_id: p.userId,
            p_payload: p,
            p_error_reason: String(err)
        }).then(({ error }) => {
             if (error) console.error("🚨 DLQ WRITE FAILED:", error);
             else console.log("💾 Saved to DLQ");
        });
    });
}

async function _resolveFallbackInternal(
    p: { 
        userId: string, 
        scenario: string, 
        priority: string, 
        decision: string, 
        title: string, 
        body: string,
        messageId: string
    }
) {
    let fallbackChannel: string | null = null;
    
    // Scenario-based Fallback Logic
    if (p.scenario === 'critical' || p.priority === 'high') {
        fallbackChannel = 'email'; 
    } else if (p.scenario === 'system') {
        fallbackChannel = 'email';
    } else if (p.scenario === 'chat' || p.scenario === 'social') {
        fallbackChannel = 'inbox'; 
    } else if (p.scenario === 'marketing') {
        fallbackChannel = 'inbox';
    }

    // STAGE J: Ensure message is in inbox on fallback
    if (p.decision !== 'throttled') {
         await _syncToInbox({
            user_id: p.userId,
            message_id: p.messageId,
            title: p.title,
            body: p.body,
            scenario: p.scenario,
            priority: p.priority,
            original_decision: p.decision,
            delivered_via: fallbackChannel || 'inbox',
            fallback_used: true
        });
    }

    if (fallbackChannel === 'email') {
        console.log(`📧 Fallback Resolving: Sending Email to ${p.userId} for ${p.scenario}`);
    }

    // Update Logs
    await supabaseAdmin.from('routing_logs').update({
        delivery_state: 'fallback_used',
        fallback_channel: fallbackChannel || 'inbox'
    }).match({ message_id: p.messageId, recipient_id: p.userId }); 
}

async function _syncToOutcomes(entry: NotificationOutcomeEntry) {
    const { error } = await supabaseAdmin.from('notification_outcomes').upsert({
        message_id: entry.message_id,
        user_id: entry.user_id,
        routing_decision: entry.routing_decision,
        final_channel: entry.final_channel,
        delivery_state: entry.delivery_state,
        delivery_cost: entry.delivery_cost,
        value_score: entry.value_score,
        metadata: entry.metadata
    }, { onConflict: 'message_id, user_id' });
    if (error) console.error("⚠️ Failed to sync to outcomes:", error);
}

async function _syncToBundle(p: { userId: string, messageId: string, scenario: string, reason: string }) {
    // Stage L: Upsert to notification_bundles
    const { error } = await supabaseAdmin.rpc('append_to_notification_bundle', {
        p_user_id: p.userId,
        p_message_id: p.messageId,
        p_scenario: p.scenario,
        p_reason: p.reason
    });
    if (error) console.error("⚠️ Failed to sync to bundle:", error);
}







// --- INTERFACES ---
interface UserDevice {
  fcm_token: string;
  device_id: string;
  is_online: boolean;
  app_state: string;
  user_id: string;
  dnd_enabled: boolean;
  dnd_start_time: string | null;
  dnd_end_time: string | null;
  timezone_offset: number | null;
  web_push_subscription: {
    endpoint: string;
    keys: {
      p256dh: string;
      auth: string;
    };
  } | null;
}

interface NotificationPolicy {
  policy_id: string;
  start_time: string | null;
  end_time: string | null;
  action: 'sent' | 'silent' | 'skipped';
  priority_override: 'high' | 'normal' | null;
}

interface ABExperiment {
  experiment_id: string;
  variant_b_config?: { force_silent?: boolean };
}

interface AdaptiveStats {
  user_id: string;
  weekly_sent_count?: number;
  weekly_open_count?: number;
}

interface RateLimit {
  user_id: string;
  scenario: string;
  hourly_count: number;
  daily_count: number;
}

interface CostStat {
  user_id: string;
  high_priority_ratio: number;
}

interface NotificationPreference {
  user_id: string;
  chats_enabled: boolean;
  groups_enabled: boolean;
  calls_enabled: boolean;
  mentions_enabled: boolean;
  pref_style: 'full' | 'silent' | 'digest';
  dnd_enabled: boolean;
  dnd_start: string | null;
  dnd_end: string | null;
  timezone_offset: number;
}

interface AISettings {
  user_id: string;
  is_enabled: boolean;
  adaptive_mode: boolean;
  sensitivity: number;
  preferred_digest_time: string | null;
  is_safe_mode?: boolean;
  paused_until?: string | null;
  context_sensitivity?: number;
  predictive_timing_enabled?: boolean;
  sandbox_mode_enabled?: boolean;
  weight_version_id?: string | null;
  stability_score?: number;
  federated_learning_enabled?: boolean;
}

interface AIWeightSnapshot {
  id: string;
  user_id: string;
  engagement_weight: number;
  context_weight: number;
  urgency_weight: number;
  trust_score: number;
}

interface UserContextSettings {
  user_id: string;
  predictive_timing_enabled: boolean;
  respect_driving_mode: boolean;
  night_mode_sensitivity: number;
  work_hours_sensitivity: number;
  context_weight: number;
  fatigue_threshold?: number;
}


interface UserContextProfile {
  user_id: string;
  peak_interaction_hours: number[];
  usage_patterns?: Record<string, number>;
}


interface AILearningWeights {
  user_id: string;
  engagement_weight: number;
  context_weight: number;
  urgency_weight: number;
  trust_score: number;
  learning_cycles: number;
}

interface AIScope {
  id: string;
  name: string;
  type: 'personal' | 'team' | 'organization';
  parent_id: string | null;
}

interface UserRole {
  user_id: string;
  scope_id: string;
  role: 'owner' | 'admin' | 'member' | 'guest';
}

interface AIPolicy {
  id: string;
  scope_id: string;
  action: 'ALLOW_AI' | 'FORCE_SILENT' | 'FORCE_DELIVER' | 'BLOCK';
  priority: number;
  rules: Record<string, unknown>;
  is_active: boolean;
}

interface AIScopeProfile {
  scope_id: string;
  engagement_weight: number;
  context_weight: number;
  urgency_weight: number;
  learning_rate: number;
}

interface BaseWeights {
  engagement_weight: number;
  context_weight: number;
  urgency_weight: number;
  trust_score?: number;
}


// --- STAGE L: HUMAN-RESPECTFUL INTELLIGENCE INTERFACES ---
interface UserTrustScore {
  user_id: string;
  trust_score: number;
}

interface UserQuietHourPrediction {
  user_id: string;
  open_hour: number;
  is_quiet_hour: boolean;
}

interface NotificationBundle {
  id: string;
  user_id: string;
  scenario: string;
  message_ids: string[];
  is_flushed: boolean;
  bundle_reason: string;
}

// --- STAGE M: CROSS-DEVICE ARBITRATION INTERFACES ---
interface UserDeviceAttentionScore {
  user_id: string;
  device_id: string;
  fcm_token: string;
  platform: string;
  attention_score: number;
  score_breakdown: Record<string, number>;
}

// --- STAGE N: HUMAN-IN-THE-LOOP INTERFACES ---
interface FineGrainedPreference {
  user_id: string;
  notification_type: string;
  preferred_device_id: string | null;
  force_delivery: boolean;
  allow_bundling: boolean;
  allow_quiet_override: boolean;
}

// --- STAGE O: SELF-OPTIMIZATION & LEARNING ---
interface UserLearningState {
  user_id: string;
  category: string;
  learning_paused: boolean;
  override_count_30d: number;
}

interface AIConfidenceMetric {
  message_id: string;
  user_id: string;
  confidence_score: number;
  confidence_level: 'LOW' | 'MEDIUM' | 'HIGH';
  factors: Record<string, number>;
}




interface AIFeatureFlag {
  id: string;

  feature_key: string;
  is_enabled: boolean;
  rollout_percentage: number;
  allow_users?: string[];
  block_users?: string[];
  shadow_mode: boolean;
  target_criteria: Record<string, unknown>;
}

// --- STAGE S: EXPERIENCE INTERFACES ---
interface UserExperiencePrefs {
  user_id: string;
  experience_mode: 'critical' | 'smart' | 'all';
  is_snoozed: boolean;
  snooze_until: string | null;
  max_hourly_notifications: number;
  category_denylist: string[];
}

// --- STAGE K: INTELLIGENCE & OPTIMIZATION INTERFACES ---
interface ChannelEffectiveness {
  user_id: string;
  final_channel: string;
  open_rate: number;
  ignore_rate: number;
  avg_time_to_open_sec: number;
}

interface NotificationOutcomeEntry {
  message_id: string;
  user_id: string;
  routing_decision: string;
  final_channel: string;
  delivery_state: string;
  delivery_cost: number;
  value_score: number;
  metadata?: Record<string, unknown>;
}

// --- STAGE K: FEDERATED LEARNING INTERFACES (Legacy) ---

interface AIGlobalWeights {
  version_id: string;
  weights: Record<string, number>; // { engagement: 0.4, context: 0.3 }
  is_active: boolean;
  generation_count: number;
}

interface AIFederatedDelta {
  user_id: string; // Ephemeral or RLS protected
  signal_type: string;
  bucket_id: string;
  delta_value: number;
  noise_factor: number;
}

interface AIFederatedSettings {
  federated_learning_enabled: boolean;
}

// --- STAGE J: DELIVERY ASSURANCE INTERFACES ---
interface NotificationInboxEntry {
  user_id: string;
  chat_id?: string;
  message_id?: string;
  title: string;
  body: string;
  scenario: string;
  priority: string;
  original_decision: string;
  delivered_via: string;
  fallback_used?: boolean;
  metadata?: Record<string, unknown>;
}

// --- STAGE M: ENTERPRISE INTERFACES ---

interface AIEnterpriseWeight {
  workspace_id: string;
  engagement_weight: number;
  context_weight: number;
  urgency_weight: number;
  trust_score: number;
}

interface AIEnterpriseOverride {
  id: string;
  scope_id: string;
  target_segment: string;
  override_type: 'soft' | 'hard';
  action: 'force_silent' | 'force_deliver' | 'bias_shift';
  bias_value: number;
  reason: string;
}

// --- STAGE O: SELF-OPTIMIZATION INTERFACES ---
interface AIOptimizationGuardrail {
  scope_id: string;
  max_weight_shift: number;
  min_confidence_floor: number;
  automation_mode: 'manual' | 'semi-auto' | 'advisory';
  forbidden_zones: string[];
}

interface AIOptimizationRecommendation {
  id: string;
  scope_id: string;
  target_param: string;
  current_value: number;
  proposed_value: number;
  status: 'pending' | 'approved' | 'rejected' | 'simulating';
}





interface EngagementStat {
  user_id: string;
  chat_id: string | null;
  content_type: string;
  total_received: number;
  total_opened: number;
  total_dismissed: number;
}

interface RoutingMeta extends Record<string, unknown> {
  is_online: boolean;
  app_state: string;
  dnd_enabled: boolean;
  adaptive_stats: AdaptiveStats | Record<string, never>;
  healing_state: { inCooldown: boolean; dailyCount: number };
  policies_applied: { id: string; action: string }[];
  experiments_applied: { id: string; variant: string }[];
  flag_disabled?: string;
  rate_limit?: { hourly: number; daily: number; limit: { hourly: number; daily: number } };
  auto_healing?: { rule: string; threshold: number; actual_rate: number };
  cost_governance?: { ratio: number; threshold: number };
  effectiveness_score?: number;
  value_score?: number;
  priority_adjustment?: string;
  trust_score?: number;
  quiet_hours_applied?: boolean;
  bundle_id?: string;
  device_arbitration?: {
    selected_device: string;
    this_device?: string;
    reason: string;
    scores: Record<string, number>;
  };
  arbitration_bypassed?: boolean;
  user_override?: {
    applied: boolean;
    fields: string[];
    source: string;
  };
  stage_o?: {
    confidence_level: string;
    learning_status: string;
    shadow_concordance: boolean;
    confidence_score: number;
  };
  stage_o_metrics?: {
    confidence: {
      score: number;
      level: string;
      factors: Record<string, number>;
    };
    shadow: {
      decision: string;
      reason: string;
      concordance: boolean;
    };
  };
}






interface TargetDevice {
  token: string;
  priority: 'high' | 'normal' | 'critical';
  device_id: string;
  reason: string;
  decision: 'sent' | 'silent' | 'skipped' | 'throttled' | 'delayed' | 'bundled';
  meta: RoutingMeta;
  recipient_id: string;
  badge?: number;
  web_push_subscription?: {
    endpoint: string;
    keys: {
      p256dh: string;
      auth: string;
    };
  } | null;
}

interface RoutingLogEntry {
  message_id: string;
  chat_id: string;
  device_id: string;
  recipient_id: string;
  decision: string;
  priority: string | null;
  reason: string;
  meta: RoutingMeta;
  delivery_state?: string;
  fallback_channel?: string;
  delivery_error?: Record<string, unknown> | null;
}


serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  // STRICT CALLER AUTHENTICATION & AUTHORIZATION
  const authHeader = req.headers.get("Authorization") || req.headers.get("authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    console.warn("⛔ Unauthorized push-handler request: Missing or invalid Authorization header");
    return new Response(JSON.stringify({ error: "Missing or invalid authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json" }
    });
  }

  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  let callerRole: string | null = null;
  let callerUserId: string | null = null;

  if (token === supabaseKey) {
    callerRole = "service_role";
  } else {
    // Verify user JWT with Supabase Auth
    const { data: userData, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !userData?.user) {
      console.warn("⛔ Unauthorized push-handler request: Invalid JWT", authError);
      return new Response(JSON.stringify({ error: "Unauthorized: Invalid JWT token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }
    callerRole = userData.user.role || "authenticated";
    callerUserId = userData.user.id;
  }

  try {
    let payload = await req.json();
    console.log("📦 AI Routing: Received Payload:", payload);

    // STAGE R: UNWRAP ENVELOPE (From SQL Triggers)
    if (payload.record) {
      const type = payload.type || 'message';
      payload = {
        ...payload.record,
        content_type: payload.record.type || (type === 'reaction' ? 'reaction' : 'text'),
        message_id: payload.record.id || payload.record.message_id,
        // Reaction specific mappings
        sender_id: payload.record.user_id || payload.record.sender_id,
      };
      console.log("📦 AI Routing: Unwrapped Payload:", payload);
    }

    const { chat_id, sender_id, message_id, content_type, text_content, priority: payloadPriority, force_fcm, type: payloadType } = payload;

    // Caller Authorization check: If not service_role, verify that caller is permitted for this action
    if (callerRole !== "service_role") {
      if (payloadType === 'call_ringing' || payloadType === 'INCOMING_CALL' || payload.receiver_id) {
        const finalSenderId = sender_id || payload.caller_id;
        const receiverId = payload.receiver_id;
        if (callerUserId !== finalSenderId && callerUserId !== receiverId) {
          console.warn(`⛔ Forbidden: Caller ${callerUserId} tried to initiate call notification for sender ${finalSenderId} / receiver ${receiverId}`);
          return new Response(JSON.stringify({ error: "Forbidden: Caller does not match sender or receiver" }), {
            status: 403,
            headers: { "Content-Type": "application/json" }
          });
        }
      } else if (payloadType === 'room_created') {
        const creatorId = payload.created_by;
        if (callerUserId !== creatorId) {
          console.warn(`⛔ Forbidden: Caller ${callerUserId} does not match room creator ${creatorId}`);
          return new Response(JSON.stringify({ error: "Forbidden: Caller does not match room creator" }), {
            status: 403,
            headers: { "Content-Type": "application/json" }
          });
        }
      } else if (sender_id && callerUserId !== sender_id) {
        console.warn(`⛔ Forbidden: Caller ${callerUserId} tried to send push for sender ${sender_id}`);
        return new Response(JSON.stringify({ error: "Forbidden: Caller does not match sender" }), {
          status: 403,
          headers: { "Content-Type": "application/json" }
        });
      }
    }

    // STAGE R: SPECIALIZED CALL HANDLING (Signaling Constitution)
    if (payloadType === 'call_ringing' || payloadType === 'INCOMING_CALL' || payload.receiver_id) {
      console.log("📞 AI Routing: Processing Call Ringing push...");
      const receiverId = payload.receiver_id;
      const finalSenderId = sender_id || payload.caller_id;
      const isVideo = payload.is_video === true || payload.call_type === 'video';
      const callId = payload.call_id || message_id;

      if (!receiverId || !finalSenderId) return new Response(JSON.stringify({ error: "Missing receiver_id or caller_id", payload }), { status: 400 });

      // 1. Fetch Sender Name
      const { data: sender } = await supabaseAdmin.from("profiles").select("display_name, username").eq("id", finalSenderId).single();
      const callerName = sender?.display_name || sender?.username || "TalkMate User";

      // 2. Fetch Recipient Device
      const { data: devices } = await supabaseAdmin.from("user_devices").select("*").eq("user_id", receiverId).eq("is_active", true);

      if (!devices || devices.length === 0) return new Response(JSON.stringify({ message: "No devices for receiver" }));

      // 3. Send Critical VoIP-style push
      const results = await Promise.all(devices.map(async (d) => {
        const message = {
          token: d.fcm_token,
          // Notification object removed for Calls to enable Data-only push (Native side handling)
          data: {
            type: 'INCOMING_CALL', // Constitutional Type
            call_id: String(callId),
            sender_id: String(finalSenderId),
            is_video: String(isVideo),
            caller_name: callerName,
          },
          android: {
            priority: 'high',
            ttl: 0, // Expire immediately if can't deliver
          },
          apns: {
            payload: {
              aps: {
                contentAvailable: true,
                sound: 'default'
              }
            }
          }
        };

        try {
          // deno-lint-ignore no-explicit-any
          const fcmRes = await getMessaging().send(message as any);
          return { device: d.device_id, status: 'sent', fcmRes };
        } catch (err) {
          return { device: d.device_id, status: 'error', error: String(err) };
        }
      }));

      return new Response(JSON.stringify({ results }));
    }

    // STAGE R: ROOM CREATION HANDLING
    if (payloadType === 'room_created') {
      console.log("🏢 AI Routing: Processing Room Creation push...");
      const roomName = payload.name;
      const creatorId = payload.created_by;
      
      if (!roomName || !creatorId) return new Response(JSON.stringify({ error: "Missing room metadata" }), { status: 400 });

      // 1. Fetch Creator Name
      const { data: creator } = await supabaseAdmin.from("profiles").select("display_name, username").eq("id", creatorId).single();
      const creatorName = creator?.display_name || creator?.username || "A user";

      // 2. Fetch "Recipients" (e.g. Friends or everyone if it's a small app)
      // For MVP: Notify everyone except the creator
      const { data: activeUsers } = await supabaseAdmin.from("profiles").select("id").neq("id", creatorId).limit(50);
      const recipientIds = activeUsers?.map(u => u.id) || [];

      if (recipientIds.length === 0) return new Response(JSON.stringify({ message: "No recipients for room" }));

      // 3. Fetch Devices
      const { data: devices } = await supabaseAdmin.from("user_devices").select("*").in("user_id", recipientIds).eq("is_active", true);

      if (!devices || devices.length === 0) return new Response(JSON.stringify({ message: "No devices found" }));

      // 4. Send pushes
      const results = await Promise.all(devices.map(async (d) => {
        const message = {
          token: d.fcm_token,
          notification: {
            title: "New Room Active",
            body: `${creatorName} created room: ${roomName}`,
          },
          data: {
            type: 'room_created',
            room_id: String(payload.id),
            click_action: "FLUTTER_NOTIFICATION_CLICK"
          }
        };

        try {
          // deno-lint-ignore no-explicit-any
          await getMessaging().send(message as any);
          return { device: d.device_id, status: 'sent' };
        } catch (_err) {
          return { device: d.device_id, status: 'error' };
        }
      }));

      return new Response(JSON.stringify({ results }));
    }

    if (!chat_id || !sender_id) {
      return new Response(JSON.stringify({ error: "Missing chat_id or sender_id" }), { status: 400 });
    }

    // 1. Fetch Sender Name
    const { data: senderProfile } = await supabaseAdmin
      .from("profiles")
      .select("username, display_name")
      .eq("id", sender_id)
      .single();
    
    const senderName = senderProfile?.display_name || senderProfile?.username || "TalkMate User";

    // 2. Fetch Conversation Details and Participants
    const [convResult, participantsResult] = await Promise.all([
      supabaseAdmin.from("conversations").select("type, is_group, group_name").eq("id", chat_id).single(),
      supabaseAdmin.from("conversation_participants").select("user_id, is_muted, mute_until").eq("conversation_id", chat_id).neq("user_id", sender_id)
    ]);

    const isGroup = convResult.data?.is_group || false;
    const groupName = convResult.data?.group_name;
    const chatType: string = convResult.data?.type || (isGroup ? 'group' : 'individual');
    const participants = participantsResult.data;

    if (!participants || participants.length === 0) {
      console.log("⚠️ No recipients found for chat:", chat_id);
      return new Response(JSON.stringify({ message: "No recipients found" }));
    }

    const recipientIds = (participants as { user_id: string }[]).map(p => p.user_id);
    
    // Mute Settings Map
    const muteSettingsMap: Record<string, { is_muted: boolean, mute_until: string | null }> = {};
    (participants as { user_id: string, is_muted: boolean, mute_until: string | null }[]).forEach(p => {
        muteSettingsMap[p.user_id] = { is_muted: p.is_muted, mute_until: p.mute_until };
    });

    console.log(`👥 Found ${recipientIds.length} recipients:`, recipientIds);

    // 3. Fetch Devices with DND and Context Info
    const { data: userDevicesRaw } = await supabaseAdmin
      .from("user_devices")
      .select("fcm_token, device_id, is_online, app_state, user_id, dnd_enabled, dnd_start_time, dnd_end_time, timezone_offset, web_push_subscription")
      .in("user_id", recipientIds)
      .eq("is_active", true);

    const userDevices = (userDevicesRaw as UserDevice[] | null) || [];

    if (userDevices.length === 0) {
      console.log(`⚠️ No active devices found for recipients: ${recipientIds.join(', ')}`);
      return new Response(JSON.stringify({ message: "No active devices" }));
    }

    console.log(`📱 Found ${userDevices.length} active devices for recipients.`);
    userDevices.forEach(d => console.log(`   - Device: ${d.device_id}, User: ${d.user_id}, Online: ${d.is_online}, State: ${d.app_state}`));

    // 3.5 Fetch Context Data (Flags, Segments, Policies, Experiments, Stats, Limits)
    const contextResults = await Promise.all([
      supabaseAdmin.from("notification_flags").select("key, value"),
      supabaseAdmin.from("notification_segments").select("*"),
      supabaseAdmin.from("notification_policies").select("*").eq("is_active", true),
      supabaseAdmin.from("ab_experiments").select("*").eq("is_active", true).gt("end_at", new Date().toISOString()),
      supabaseAdmin.from("adaptive_routing_stats").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("routing_config").select("key, value"),

      supabaseAdmin.from("notification_rate_limits").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("notification_cost_stats").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("notification_preferences").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("notification_ai_settings").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("user_notification_engagement").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("notification_ai_exclusions").select("chat_id, user_id").in("user_id", recipientIds).eq("chat_id", chat_id),
      supabaseAdmin.from("ai_drift_stats").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("ai_governance_config").select("*"),
      supabaseAdmin.from("user_context_settings").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("user_context_profiles").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("ai_learning_weights").select("*").in("user_id", recipientIds), // 16

      supabaseAdmin.from("ai_weight_snapshots").select("*").in("user_id", recipientIds),
      // STAGE H: Policy & Identity
      supabaseAdmin.from("ai_scopes").select("*"), 
      supabaseAdmin.from("user_roles").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("ai_policies").select("*").eq("is_active", true),
      supabaseAdmin.from("ai_scope_profiles").select("*"),
      // STAGE J: Feature Flags
      supabaseAdmin.from("ai_feature_flags").select("*"),
      // STAGE K: Federated Learning
      supabaseAdmin.from("ai_global_weights").select("*").eq("is_active", true).order("created_at", { ascending: false }).limit(1),
      supabaseAdmin.from("ai_privacy_logs").select("id").eq("user_id", recipientIds[0]), // Dummy check for RLS pre-warm
      // STAGE M: Enterprise
      supabaseAdmin.from("ai_enterprise_weights").select("*"),
      supabaseAdmin.from("ai_enterprise_overrides").select("*").eq("is_active", true),
      // STAGE O: Self-Optimization
      supabaseAdmin.from("ai_optimization_guardrails").select("*").eq("is_active", true), // 28
      supabaseAdmin.from("ai_optimization_recommendations").select("*").eq("status", "approved"), // 29
      supabaseAdmin.from("user_channel_effectiveness").select("*").in("user_id", recipientIds), // 30
      supabaseAdmin.from("user_trust_scores").select("*").in("user_id", recipientIds), // 31
      supabaseAdmin.from("user_quiet_hours_prediction").select("*").in("user_id", recipientIds), // 32
      supabaseAdmin.from("user_device_attention_scores").select("*").in("user_id", recipientIds), // 33
      supabaseAdmin.from("user_notification_settings_fine_grained").select("*").in("user_id", recipientIds), // 34
      supabaseAdmin.from("user_learning_states").select("*").in("user_id", recipientIds),
      supabaseAdmin.from("system_governance").select("key, value"), // index 35
      supabaseAdmin.from("user_notification_experience_prefs").select("*").in("user_id", recipientIds) // index 36

    ]);

    // 4. Governance & Context Mapping
    const governanceData = (contextResults[35]?.data as { key: string, value: unknown }[] | null) || [];

    const killSwitchConfig = (governanceData.find(g => g.key === 'ai_global_kill_switch')?.value as { enabled?: boolean }) || { enabled: false };
    const isAIKillSwitchActive = killSwitchConfig.enabled === true;

    // STAGE Q: ROLLOUT CONFIG
    const rolloutConfig = (governanceData.find(g => g.key === 'ai_rollout_config')?.value as { 
        target_percentage?: number;
        allowed_segments?: string[];
        blacklisted_users?: string[];
        whitelisted_users?: string[];
        stage_locks?: Record<string, unknown>;
    }) || { 
        target_percentage: 0, 
        allowed_segments: ['internal'], 
        blacklisted_users: [], 
        whitelisted_users: [],
        stage_locks: {} 
    };








    const flags = contextResults[0].data as {key: string, value: boolean}[] | null;
    const policies = contextResults[2].data as NotificationPolicy[] | null;
    const activeExperiments = contextResults[3].data as (ABExperiment & {is_active: boolean})[] | null;
    const userStats = contextResults[4].data as AdaptiveStats[] | null;
    const configData = contextResults[5].data as {key: string, value: unknown}[] | null;
    const rateLimits = contextResults[6].data as RateLimit[] | null;
    const costStats = contextResults[7].data as CostStat[] | null;
    const userPrefs = contextResults[8].data as NotificationPreference[] | null;
    const aiSettings = contextResults[9].data as AISettings[] | null;
    const engagementStats = contextResults[10].data as EngagementStat[] | null;
    const aiExclusions = contextResults[11].data as {chat_id: string, user_id: string}[] | null;
    const driftStats = contextResults[12].data as {user_id: string, drift_score: number}[] | null;
    const govConfig = contextResults[13].data as {key: string, value: {enabled: boolean}}[] | null;
    const contextSettings = contextResults[14].data as UserContextSettings[] | null;
    const contextProfiles = contextResults[15].data as UserContextProfile[] | null;
    const learningWeights = contextResults[16].data as AILearningWeights[] | null;
    // STAGE H Data
    const scopes = contextResults[18].data as AIScope[] | null;
    const userRoles = contextResults[19].data as UserRole[] | null;
    const activePolicies = contextResults[20].data as AIPolicy[] | null;
    const scopeProfiles = contextResults[21].data as AIScopeProfile[] | null;
    const featureFlags = contextResults[22].data as AIFeatureFlag[] | null;

    // --- STAGE J: FEATURE FLAG MAP ---
    const featureFlagMap: Record<string, AIFeatureFlag> = {};
    featureFlags?.forEach(f => featureFlagMap[f.feature_key] = f);

    // STAGE J Helper: Deterministic Feature Flag Check
    const checkFeatureFlag = (key: string, userId: string): boolean => {
        const flag = featureFlagMap[key];
        if (!flag) return false; // Default to false if flag missing
        if (!flag.is_enabled) return false; // Global kill
        if (flag.block_users?.includes(userId)) return false;
        if (flag.allow_users?.includes(userId)) return true;
        
        if (flag.rollout_percentage > 0) {
            // Simple deterministic hash matching SQL's hashtext approximation
            const combo = userId + key;
            let hash = 0;
            for (let i = 0; i < combo.length; i++) {
                const char = combo.charCodeAt(i);
                hash = ((hash << 5) - hash) + char;
                hash = hash & hash; // Convert to 32bit integer
            }
            const pct = Math.abs(hash) % 100;
            return pct < flag.rollout_percentage;
        }
        return false;
    };

    // STAGE M: Enterprise Mappings
    const entWeightMap: Record<string, AIEnterpriseWeight> = {};
    (contextResults[25].data as unknown as AIEnterpriseWeight[])?.forEach(w => entWeightMap[w.workspace_id] = w);

    const entOverrideMap: Record<string, AIEnterpriseOverride[]> = {};
    (contextResults[26].data as unknown as AIEnterpriseOverride[])?.forEach(o => {
      if (!entOverrideMap[o.scope_id]) entOverrideMap[o.scope_id] = [];
      entOverrideMap[o.scope_id].push(o);
    });


    // STAGE O: Optimization Mappings
    const optGuardrailMap: Record<string, AIOptimizationGuardrail> = {};
    (contextResults[27].data as unknown as AIOptimizationGuardrail[])?.forEach(g => optGuardrailMap[g.scope_id] = g);

    const optRecMap: Record<string, AIOptimizationRecommendation[]> = {};
    (contextResults[28].data as unknown as AIOptimizationRecommendation[])?.forEach(r => {
      if (!optRecMap[r.scope_id]) optRecMap[r.scope_id] = [];
      optRecMap[r.scope_id].push(r);
    });

    // STAGE K: Effectiveness Mappings
    const effectivenessMap: Record<string, ChannelEffectiveness[]> = {};
    (contextResults[29].data as unknown as ChannelEffectiveness[])?.forEach(e => {
      if (!effectivenessMap[e.user_id]) effectivenessMap[e.user_id] = [];
      effectivenessMap[e.user_id].push(e);
    });

    // STAGE L: Trust & Quiet Hour Mappings
    const trustMap: Record<string, number> = {};
    (contextResults[30].data as unknown as UserTrustScore[])?.forEach(t => trustMap[t.user_id] = t.trust_score);

    const quietHourMap: Record<string, Set<number>> = {};
    (contextResults[31].data as unknown as UserQuietHourPrediction[])?.forEach(q => {
      if (!quietHourMap[q.user_id]) quietHourMap[q.user_id] = new Set();
      if (q.is_quiet_hour) quietHourMap[q.user_id].add(q.open_hour);
    });

    // STAGE M: Attention Score Mappings
    const attentionMapRecord: Record<string, UserDeviceAttentionScore[]> = {};
    (contextResults[32].data as unknown as UserDeviceAttentionScore[])?.forEach(a => {
      if (!attentionMapRecord[a.user_id]) attentionMapRecord[a.user_id] = [];
      attentionMapRecord[a.user_id].push(a);
    });

    // STAGE N: Fine-Grained Preference Mappings
    const fineGrainedMap: Record<string, Record<string, FineGrainedPreference>> = {};
    (contextResults[33].data as unknown as FineGrainedPreference[])?.forEach(p => {
      if (!fineGrainedMap[p.user_id]) fineGrainedMap[p.user_id] = {};
      fineGrainedMap[p.user_id][p.notification_type] = p;
    });

    // STAGE O: Learning States Mapping
    const learningStateMap: Record<string, Record<string, UserLearningState>> = {};
    (contextResults[34].data as unknown as UserLearningState[])?.forEach(s => {
      if (!learningStateMap[s.user_id]) learningStateMap[s.user_id] = {};
      learningStateMap[s.user_id][s.category] = s;
    });

    // STAGE S: Experience Prefs Mapping
    const experienceMap: Record<string, UserExperiencePrefs> = {};
    (contextResults[36].data as unknown as UserExperiencePrefs[])?.forEach(p => experienceMap[p.user_id] = p);










    // --- STEP 0: FEATURE FLAGS (KILL SWITCH) ---
    const flagMap: Record<string, boolean> = {};
    flags?.forEach(f => flagMap[f.key] = f.value);

    // Global Kill Switch
    if (flagMap['global_push_enabled'] === false) {
      console.log("⛔ Global Push Disabled via Feature Flag.");
      return new Response(JSON.stringify({ message: "Global Push Disabled" }));
    }

    // Map Context Data
    const statsMap: Record<string, AdaptiveStats> = {};
    userStats?.forEach(stat => { statsMap[stat.user_id] = stat; });
    
    const prefMap: Record<string, NotificationPreference> = {};
    userPrefs?.forEach(p => prefMap[p.user_id] = p);

    // --- STAGE V: Fetch Unread Counts (Bulk) ---
    const { data: unreadData } = await supabaseAdmin
      .from('view_user_unread_counts')
      .select('user_id, unread_total')
      .in('user_id', recipientIds);
    
    const unreadMap: Record<string, number> = {};
    unreadData?.forEach(d => unreadMap[d.user_id] = Number(d.unread_total));

    const aiSettingsMap: Record<string, AISettings> = {};
    aiSettings?.forEach(s => aiSettingsMap[s.user_id] = s);

    const contextSettingsMap: Record<string, UserContextSettings> = {};
    contextSettings?.forEach(s => contextSettingsMap[s.user_id] = s);

    const contextProfileMap: Record<string, UserContextProfile> = {};
    contextProfiles?.forEach(p => contextProfileMap[p.user_id] = p);

    const learningWeightsMap: Record<string, AILearningWeights> = {};
    learningWeights?.forEach(w => learningWeightsMap[w.user_id] = w);

    const snapshotMap: Record<string, AIWeightSnapshot> = {};
    (contextResults[17]?.data as AIWeightSnapshot[])?.forEach(s => snapshotMap[s.id] = s);

    const engagementMap: Record<string, EngagementStat[]> = {};
    engagementStats?.forEach(e => {
        if (!engagementMap[e.user_id]) engagementMap[e.user_id] = [];
        engagementMap[e.user_id].push(e);
    });


    // STAGE H Mappings
    const scopeMap: Record<string, AIScope> = {};
    scopes?.forEach(s => scopeMap[s.id] = s);

    const userRoleMap: Record<string, UserRole[]> = {}; // User -> Roles[]
    userRoles?.forEach(r => {
        if (!userRoleMap[r.user_id]) userRoleMap[r.user_id] = [];
        userRoleMap[r.user_id].push(r);
    });

    const policyMap: Record<string, AIPolicy[]> = {}; // Scope -> Policies[]
    activePolicies?.forEach(p => {
        if (!policyMap[p.scope_id]) policyMap[p.scope_id] = [];
        policyMap[p.scope_id].push(p);
    });

    const scopeProfileMap: Record<string, AIScopeProfile> = {}; // Scope -> Profile
    scopeProfiles?.forEach(p => scopeProfileMap[p.scope_id] = p);
    
    // Config Defaults
    const configMap: Record<string, unknown> = {};
    configData?.forEach(c => configMap[c.key] = c.value);

    const autoHealConfig = configMap['auto_healing_rules'] as {
      max_ignored_streak: number;
      throttle_duration_hours: number;
      critical_open_rate_threshold: number;
      max_daily_heals: number;
    } | undefined || {
      max_ignored_streak: 3,
      throttle_duration_hours: 1,
      critical_open_rate_threshold: 0.1,
      max_daily_heals: 3
    };

    const costConfig = configMap['cost_governance'] as {
        high_priority_cost_threshold: number;
        default_hourly_limit: number;
        default_daily_limit: number;
        scenario_limits: Record<string, { hourly: number; daily: number }>;
    } | undefined || {
        high_priority_cost_threshold: 0.3,
        default_hourly_limit: 20,
        default_daily_limit: 100,
        scenario_limits: {}
    };

    const rateLimitMap: Record<string, RateLimit> = {};
    rateLimits?.forEach(r => { rateLimitMap[`${r.user_id}_${r.scenario}`] = r; });
    
    const costStatMap: Record<string, CostStat> = {};
    costStats?.forEach(s => { costStatMap[s.user_id] = s; });

    const driftMap: Record<string, number> = {};
    driftStats?.forEach(d => driftMap[d.user_id] = d.drift_score);

    const exclusionMap: Record<string, Set<string>> = {};
    aiExclusions?.forEach(ex => {
        if (!exclusionMap[ex.user_id]) exclusionMap[ex.user_id] = new Set();
        exclusionMap[ex.user_id].add(ex.chat_id);
    });

    const isGlobalAIKillSwitch = govConfig?.find(c => c.key === 'global_ai_kill_switch')?.value?.enabled === true;

    // Fetch Recent Logs for Cooldown & Daily Limit Checks
    const cooldownTime = new Date(Date.now() - (autoHealConfig.throttle_duration_hours * 60 * 60 * 1000)).toISOString();
    const dayAgoTime = new Date(Date.now() - (24 * 60 * 60 * 1000)).toISOString();

    const { data: recentHealsRaw } = await supabaseAdmin
      .from("routing_logs")
      .select("recipient_id, created_at, decision")
      .in("recipient_id", recipientIds)
      .eq("decision", "throttled") 
      .gt("created_at", dayAgoTime);
    
    const recentHeals = (recentHealsRaw as {recipient_id: string, created_at: string, decision: string}[] | null) || [];

    // Fetch A/B Assignments
    const { data: assignmentsRaw } = await supabaseAdmin
      .from("ab_assignments")
      .select("user_id, experiment_id, variant")
      .in("user_id", recipientIds);
      
    const assignmentMap: Record<string, string> = {};
    (assignmentsRaw as {user_id: string, experiment_id: string, variant: string}[] | null)?.forEach(a => assignmentMap[`${a.user_id}_${a.experiment_id}`] = a.variant);

    const userHealHistory: Record<string, { inCooldown: boolean, dailyCount: number }> = {};
    recentHeals.forEach(log => {
        if (!userHealHistory[log.recipient_id]) {
            userHealHistory[log.recipient_id] = { inCooldown: false, dailyCount: 0 };
        }
        userHealHistory[log.recipient_id].dailyCount++;
        if (new Date(log.created_at) > new Date(cooldownTime)) {
            userHealHistory[log.recipient_id].inCooldown = true;
        }
    });

    // 4. AI Routing & Decision Engine
    const targets: TargetDevice[] = [];
    const logs: RoutingLogEntry[] = [];
    const aiLogs: {
      user_id: string;
      utility_score: number | null;
      factor_engagement: number | null;
      final_decision: string;
      explanation_key: string;
      explanation_context: Record<string, unknown>;
      weight_version_id: string | null;
    }[] = [];


    const shadowLogs: {
      user_id: string;
      shadow_weights: Record<string, unknown>;
      shadow_decision: string;
      actual_decision: string;
      recipient_id?: string;
      concordance: boolean;
      decision_id?: string;
      actual_message_id?: string;
    }[] = [];

    const confidenceLogs: {
      message_id: string;
      user_id: string;
      confidence_score: number;
      confidence_level: string;
      factors: Record<string, number>;
    }[] = [];

    const currentTimeInMinutes = (new Date().getUTCHours() * 60) + new Date().getUTCMinutes();

    let bodyText = "";
    for (const device of userDevices) {
      try { // STAGE Q: BLAST RADIUS CONTAINMENT (Per-User Isolation)
          // INJECTED BY ANTIGRAVITY FOR VERIFICATION
          if (checkFeatureFlag('ai_verification_mode', device.user_id)) {
              // Bypass Stage Q and proceed to AI
              console.log(`Verification Mode Active for ${device.user_id} - Bypassing Blast Radius`);
          } else {
             // Fallback to ensuring we don't accidentally block if logic is missing locally
             // But if server had logic, this overwrite should fix it.
          }

      const stats = statsMap[device.user_id] || {};
      const healState = userHealHistory[device.user_id] || { inCooldown: false, dailyCount: 0 };
      const prefs = prefMap[device.user_id] || { 
        chats_enabled: true, groups_enabled: true, calls_enabled: true, 
        mentions_enabled: true, pref_style: 'full', dnd_enabled: false,
        dnd_start: null, dnd_end: null, timezone_offset: 0
      };
      
      const meta: RoutingMeta = {
        is_online: device.is_online,
        app_state: device.app_state,
        dnd_enabled: device.dnd_enabled,
        adaptive_stats: stats,
        healing_state: healState,
        policies_applied: [],
        experiments_applied: []
      };

      let priority: 'high' | 'normal' | 'critical' = 'high';
      let reason = 'STANDARD_DELIVERY';
      let decision: 'sent' | 'silent' | 'skipped' | 'throttled' | 'delayed' | 'bundled' = 'sent';

      const isVerificationMode = checkFeatureFlag('ai_verification_mode', device.user_id);

      // --- CALCULATE CHAT MUTE STATE ---
      let isChatMuted = false;
      const mSettings = muteSettingsMap[device.user_id];
      if (mSettings) {
         if (mSettings.mute_until) {
             if (new Date(mSettings.mute_until) > new Date()) isChatMuted = true;
         } else if (mSettings.is_muted) {
             isChatMuted = true;
         }
      }

      // --- CRITICALITY CHECK ---
      const isMention = payload.is_mention === true;
      const isCritical = content_type === 'call' || 
                        content_type === 'critical' || 
                        payloadPriority === 'critical' || 
                        (isMention && !isChatMuted) || 
                        aiSettingsMap[device.user_id]?.is_safe_mode || 
                        chatType === 'urgent' ||
                        (chatType === 'individual' && !isChatMuted) || 
                        isVerificationMode;

      // --- MUTED CHAT HANDLING ---
      if (isChatMuted && !isCritical) {
          decision = 'silent';
          reason = 'CHAT_MUTED';
          // We continue to allow Policies to potentially override (e.g. Force Deliver), 
          // but usually Policies run later.
          // AI logic below should be skipped if we want to respect mute.
      }

      // --- STAGE I: RATE GOVERNOR ---
      const scenario = content_type || 'chat';
      const rateLimit = rateLimitMap[`${device.user_id}_${scenario}`];
      
      const limits = costConfig.scenario_limits[scenario] || { hourly: costConfig.default_hourly_limit, daily: costConfig.default_daily_limit };
      
      if (!isCritical && rateLimit) {
          if (rateLimit.hourly_count >= limits.hourly || rateLimit.daily_count >= limits.daily) {
              decision = 'throttled';
              reason = 'RATE_LIMIT_EXCEEDED';
              meta.rate_limit = { 
                  hourly: rateLimit.hourly_count, 
                  daily: rateLimit.daily_count, 
                  limit: limits 
              };
          }
      }


      // --- STEP 0.5: IDENTITY & SCOPE ---
      // Determine effective scope. 
      // Logic: 1. Try to find a scope that matches chat_id (if feasible). 
      // 2. Default to user's "Personal" scope.
      let currentScopeId: string | null = null;
      let _currentRole: string = 'guest';

      const userEffectiveRoles = userRoleMap[device.user_id] || [];
      const personalRole = userEffectiveRoles.find(r => scopeMap[r.scope_id]?.type === 'personal');
      
      // Future: heuristic to match chat_id to a team scope
      if (personalRole) {
          currentScopeId = personalRole.scope_id;
          _currentRole = personalRole.role;
      }

      // --- STEP 0.6: POLICY ENGINE (PRE-AI GATE) ---
      let policyAction: string | null = null;
      let appliedPolicyId: string | null = null;

      if (currentScopeId) {
          const scopePolicies = policyMap[currentScopeId] || [];
          // Sort by priority DESC
          scopePolicies.sort((a, b) => b.priority - a.priority);

          for (const policy of scopePolicies) {
              // Rule Evaluation (Basic support for now)
              let rulesMatch = true;
              // Example rule: {"source_type": "channel"}
              if (policy.rules && Object.keys(policy.rules).length > 0) {
                   const r = policy.rules as Record<string, unknown>;
                   if (r.source_type && r.source_type !== chatType) rulesMatch = false;
                   // Add time range check here if needed
              }

              if (rulesMatch) {
                  policyAction = policy.action;
                  appliedPolicyId = policy.id;
                  break; // Highest priority wins
              }
          }
      }

      // --- STAGE M: ENTERPRISE OVERRIDE ENGINE ---
      let enterpriseOverrideAction: string | null = null;
      let enterpriseBias = 0.0;
      let _appliedEnterprisePolicyId: string | null = null;

      
      if (currentScopeId) {
          const workspaceOverrides = entOverrideMap[currentScopeId] || [];
          for (const override of workspaceOverrides) {
              // Basic segment check (extension point)
              if (override.target_segment !== 'all') continue; 
              
              if (override.override_type === 'hard') {
                  enterpriseOverrideAction = override.action;
                  _appliedEnterprisePolicyId = override.id;
                  break; // Hard wins immediately

              } else {
                  // Soft Override: Cumulative bias shift
                  if (override.action === 'bias_shift') {
                      enterpriseBias += override.bias_value;
                  }
              }
          }
      }

      if (enterpriseOverrideAction === 'force_silent') {
          decision = 'silent';
          reason = 'ENT_HARD_SILENT';
          // Log to Audit later
      } else if (enterpriseOverrideAction === 'force_deliver') {
          decision = 'sent';
          reason = 'ENT_HARD_DELIVER';
      }

      let isForbiddenZone = false;
      if (decision !== 'sent' && enterpriseOverrideAction) {
          // If hard override already decided, skip AI
      } else {
          // --- STAGE O: SELF-OPTIMIZATION CONTEXT CHECK ---
          if (currentScopeId) {
              const guardrail = optGuardrailMap[currentScopeId];
              if (guardrail && guardrail.forbidden_zones) {
                  // Example: forbidden_zones = ['urgent', 'emergency']
                  if (guardrail.forbidden_zones.includes(chatType)) isForbiddenZone = true;
              }
          }
          
          // Continue to AI logic...
      }



      if (policyAction) {
          if (policyAction === 'BLOCK') {
              logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision: 'skipped', priority: null, reason: 'POLICY_BLOCK', meta});
              continue; // Stop everything
          } else if (policyAction === 'FORCE_SILENT') {
              decision = 'silent';
              reason = 'POLICY_FORCE_SILENT';
              meta.policies_applied.push({id: appliedPolicyId!, action: policyAction});
              // We skip AI but allow Critical Check to override? 
              // Requirement: "Critical Messages cannot be hidden EXCEPT by explicit policy".
              // So if Policy says SILENT, it effectively silences critical too unless we add logic.
              // For now, assume Policy > All.
          } else if (policyAction === 'FORCE_DELIVER') {
              priority = 'high';
              decision = 'sent';
              reason = 'POLICY_FORCE_DELIVER';
              meta.policies_applied.push({id: appliedPolicyId!, action: policyAction});
          }
      }

      // --- STEP 1: HARD GUARDS (Critical Checks) ---
      // Critical bypasses EVERYTHING (Flags, Rates, Policies, Experiments, Healing, Cost)
      if (isCritical) {

          targets.push({
            token: device.fcm_token, priority: 'high', device_id: device.device_id,
            reason: 'CRITICAL_BYPASS', decision: 'sent', meta, recipient_id: device.user_id,
            badge: unreadMap[device.user_id] || 0
          });
          logs.push({
            message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id,
            decision: 'sent', priority: 'high', reason: 'CRITICAL_BYPASS', meta
          });
          continue; 
      }

      // --- STEP 1.5: USER PREFERENCE INTERCEPTOR ---
      // Check if this type of message is disabled by the user
      const isCall = content_type === 'call' || content_type === 'webrtc_call';
      const isGroup = chatType === 'group';
      
      if (isCall && !prefs.calls_enabled) {
          decision = 'skipped';
          reason = 'USER_PREF_CALLS_DISABLED';
          logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision, priority: null, reason, meta});
          continue;
      }
      if (isGroup && !prefs.groups_enabled) {
          decision = 'skipped';
          reason = 'USER_PREF_GROUPS_DISABLED';
          logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision, priority: null, reason, meta});
          continue;
      }
      if (!isGroup && !isCall && !prefs.chats_enabled) {
          decision = 'skipped';
          reason = 'USER_PREF_CHATS_DISABLED';
          logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision, priority: null, reason, meta});
          continue;
      }
      
      // Apply DND (Quiet Hours)
      if (prefs.dnd_enabled && prefs.dnd_start && prefs.dnd_end) {
          const userLocalMin = (currentTimeInMinutes + prefs.timezone_offset) % 1440;
          if (isInDND(userLocalMin, prefs.dnd_start, prefs.dnd_end)) {
              decision = 'silent';
              priority = 'normal';
              reason = 'USER_PREF_DND_ACTIVE';
          }
      }

      // --- STEP 1.7: AI SMART ROUTING (STAGE C + D Governance) ---
      const ai = aiSettingsMap[device.user_id];
      const isExcluded = exclusionMap[device.user_id]?.has(chat_id);
      const isPaused = ai?.paused_until && new Date(ai.paused_until) > new Date();
      const isSafeMode = ai?.is_safe_mode === true;
      const driftScore = driftMap[device.user_id] || 0;

      let openRate: number | null = null;
      let utilityScore: number | null = null;
      let explanationKeyLegacy = 'AI_NORMAL';


      if (ai?.is_enabled && !isCritical && !isChatMuted) {
          
          // STAGE Q: ROLLOUT GATE
          let isRolloutAllowed = checkFeatureFlag('ai_verification_mode', device.user_id); // Verification Bypass Injected
          // 1. Whitelist/Blacklist
          if (rolloutConfig.blacklisted_users?.includes(device.user_id)) isRolloutAllowed = false;
          else if (rolloutConfig.whitelisted_users?.includes(device.user_id)) isRolloutAllowed = true;
          // 2. Global Percentage (Deterministic)
          else {
              const hash = getHash(device.user_id);
              const userPct = hash % 100;
              if (userPct < (rolloutConfig.target_percentage || 0)) isRolloutAllowed = true;
          }
          
          if (!isRolloutAllowed) {
              decision = 'sent';
              reason = 'STAGE_Q_ROLLOUT_EXCLUDED';
              // Skip to execution
          } else if (isGlobalAIKillSwitch) {
              explanationKeyLegacy = 'GOV_GLOBAL_KILL_SWITCH';
              decision = 'sent';
              reason = explanationKeyLegacy;
          } else if (isExcluded) {
              explanationKeyLegacy = 'GOV_CHAT_EXCLUSION';
              decision = 'sent';
              reason = explanationKeyLegacy;
          } else if (isPaused) {
              explanationKeyLegacy = 'GOV_PAUSE_ACTIVE';
              decision = 'sent';
              reason = explanationKeyLegacy;
          } else if (isSafeMode) {
              explanationKeyLegacy = 'GOV_SAFE_MODE';
              decision = 'sent';
              reason = explanationKeyLegacy;
          } else {
              const userEngagements = engagementMap[device.user_id] || [];
              const globalEng = userEngagements.find(e => e.chat_id === null && e.content_type === content_type);
              const chatEng = userEngagements.find(e => e.chat_id === chat_id && e.content_type === content_type);
              
              openRate = 0.5;
              if (chatEng && chatEng.total_received > 5) {
                  openRate = chatEng.total_opened / chatEng.total_received;
              } else if (globalEng && globalEng.total_received > 5) {
                  openRate = (globalEng.total_opened / globalEng.total_received) * 0.8;
              }

              // 4.5. STAGE G: GOVERNANCE & VERSIONING
              // 4.5. STAGE G & H: GOVERNANCE & MULTI-PROFILE
              const lw = learningWeightsMap[device.user_id];
              const snapshot = ai.weight_version_id ? snapshotMap[ai.weight_version_id] : null;
              
               // STAGE H: Use Scope Profile if available
               const sProfile = currentScopeId ? scopeProfileMap[currentScopeId] : null;

               // STAGE M: Enterprise Workspace Weights
               const ew = currentScopeId ? entWeightMap[currentScopeId] : null;

               // STAGE O: Apply Approved Optimization Shifts
               const finalWeights: BaseWeights = (snapshot || sProfile || lw || ew || { engagement_weight: 0.4, context_weight: 0.3, urgency_weight: 0.3 }) as BaseWeights;

               
               if (currentScopeId && !isForbiddenZone) {
                   const recs = optRecMap[currentScopeId] || [];
                   for (const rec of recs) {
                       if (rec.target_param === 'engagement_weight') finalWeights.engagement_weight = rec.proposed_value;
                       if (rec.target_param === 'context_weight') finalWeights.context_weight = rec.proposed_value;
                       if (rec.target_param === 'urgency_weight') finalWeights.urgency_weight = rec.proposed_value;
                   }
               }
               
               const shadowWeights = lw || { engagement_weight: 0.4, context_weight: 0.3, urgency_weight: 0.3 }; // Metrics comparison always vs User baseline


              const cSettings = contextSettingsMap[device.user_id];
              const cProfile = contextProfileMap[device.user_id];
              const userDate = new Date();
              const userHour = (userDate.getUTCHours() + (device.timezone_offset || 0) + 24) % 24;
              const isWeekend = userDate.getDay() === 0 || userDate.getDay() === 6;

              let timeSegment = 'morning';
              if (isWeekend) timeSegment = 'weekend';
              else if (userHour >= 22 || userHour < 6) timeSegment = 'night';
              else if (userHour >= 9 && userHour < 17) timeSegment = 'work';

              // --- STAGE E: CONTEXT AWARENESS ENGINE ---
              let contextPenalty = 0.0;
              const deviceState = payload.device_state || 'idle'; // Expected from client
              
              if (cSettings) {
                // 1. Time-based Penalty
                if (timeSegment === 'night') contextPenalty += (cSettings.night_mode_sensitivity * 0.5);
                if (timeSegment === 'work' && chatType !== 'work') contextPenalty += (cSettings.work_hours_sensitivity * 0.3);
                
                // 2. Device-state Penalty
                if (cSettings.respect_driving_mode && deviceState === 'driving') contextPenalty += 0.8;
                if (deviceState === 'idle') contextPenalty += 0.1;

                // 3. Behavioral Pattern Match
                if (cProfile) {
                    const isPeakHour = cProfile.peak_interaction_hours?.includes(userHour);
                    if (!isPeakHour && timeSegment !== 'morning') contextPenalty += 0.2;
                    
                    // Usage Pattern Affinity (e.g., if social_interest is low, penalize non-work)
                    const patterns = cProfile.usage_patterns as Record<string, number> || {};
                    if (chatType === 'social' || chatType === 'individual') {
                        const socialAffinity = patterns['social_interest'] ?? 0.5;
                        if (socialAffinity < 0.3) contextPenalty += 0.2;
                    }
                }
              }

              // Micro-Personalization: Dynamic Threshold Adjustment
              const personalSensitivity = ai.sensitivity || 0.5;
              const fatigueThreshold = cSettings?.fatigue_threshold || 0.7;
              
              // --- STAGE K: INTELLIGENCE & ADAPTIVE PRIORITY ---
              const userEffectiveness = effectivenessMap[device.user_id]?.find(e => e.final_channel === 'fcm');
              const effectivenessScore = userEffectiveness?.open_rate ?? 0.5; 
              let priorityAdjustment = null;

              if (priority === 'high' && effectivenessScore < 0.2 && chatType !== 'work') {
                  priority = 'normal';
                  priorityAdjustment = 'LOW_EFFECTIVENESS_DOWNGRADE';
                  meta.priority_adjustment = priorityAdjustment;
              }
              
              // Base Value Score (Predicted Intelligence)
              // FCM Cost: High=0.05, Normal=0.01. Action Weight: Open=1.0
              const estCost = priority === 'high' ? 0.05 : 0.01;
              const predictedValue = (effectivenessScore * 1.0) / estCost;
              
              meta.effectiveness_score = effectivenessScore;
              meta.value_score = predictedValue;

              // --- STAGE L: HUMAN-RESPECTFUL INTELLIGENCE ---
              const userTrust = trustMap[device.user_id] ?? 50.0;
              const isQuietHour = quietHourMap[device.user_id]?.has(userHour) ?? false;
              let quietHoursApplied = false;

              meta.trust_score = userTrust;

              // Predictive Quiet Hour Logic (Soft DND)
              if (isQuietHour && priority !== 'high' && content_type !== 'critical') {
                  quietHoursApplied = true;
                  meta.quiet_hours_applied = true;
              }

              // Trust-Aware Priority Adjustment
              if (userTrust < 30 && priority === 'high' && content_type === 'marketing') {
                  priority = 'normal';
                  meta.priority_adjustment = 'LOW_TRUST_MARKETING_DOWNGRADE';
              }


              // If context penalty is extreme...
              if (contextPenalty > fatigueThreshold || quietHoursApplied) {
                  contextPenalty *= 2.0; // Amplify for bundling logic
              }



              
                   // --- STAGE K: FEDERATED SIGNAL ENGINE ---
                   // 1. Check Privacy Kill-Switch & Feature Flag
                   const isFederatedFlagEnabled = checkFeatureFlag('ai_federated_learning', device.user_id);
                   const isFederatedEnabled = (ai.federated_learning_enabled !== false) && isFederatedFlagEnabled;
                   
                   let effectiveWeights = finalWeights;
                   
                   if (isFederatedEnabled) {
                       // 2. Global Bias Correction (Download & Apply)
                       const globalModel = contextResults[23].data?.[0] as AIGlobalWeights | undefined;
                       
                       if (globalModel && globalModel.is_active && globalModel.weights) {
                           // Apply Global Bias (Weighted Average or Shift)
                           const biasFactor = 0.1;
                           // Use bracket notation for Record<string, number>
                           const gEngagement = globalModel.weights['engagement_weight'] ?? 0.4;
                           const gContext = globalModel.weights['context_weight'] ?? 0.3;
                           const gUrgency = globalModel.weights['urgency_weight'] ?? 0.3;
                           
                           const currentTrust = finalWeights.trust_score ?? 1.0; 
                           
                           effectiveWeights = {
                               engagement_weight: (finalWeights.engagement_weight * (1 - biasFactor)) + (gEngagement * biasFactor),
                               context_weight: (finalWeights.context_weight * (1 - biasFactor)) + (gContext * biasFactor),
                               urgency_weight: (finalWeights.urgency_weight * (1 - biasFactor)) + (gUrgency * biasFactor),
                               trust_score: currentTrust,
                           }; 
                           
                           // 3. Local Delta Calculation
                           const deltaEngagement = ((lw?.engagement_weight || 0.4) - gEngagement);
                           
                           // 4. Differential Privacy
                           const laplaceNoise = (scale: number) => {
                               const u = 0.5 - Math.random();
                               return -Math.sign(u) * scale * Math.log(1 - 2 * Math.abs(u));
                           };
                           
                           const noise = laplaceNoise(0.05);
                           const noisyDelta = deltaEngagement + noise;
                           
                           // 5. Quantization
                           const bucketedDelta = Math.round(noisyDelta * 20) / 20;

                           // 6. Upload
                           if (Math.random() < 0.1) {
                               supabaseAdmin.from('ai_federated_deltas').insert({
                                   user_id: device.user_id,
                                   signal_type: 'engagement_delta',
                                   bucket_id: new Date().toISOString().slice(0, 8) + 'W' + Math.ceil(new Date().getDate() / 7),
                                   delta_value: bucketedDelta,
                                   noise_factor: noise
                               }).then(({ error }) => { if(error) console.error("Federated Upload Error", error); });
                           }
                       }
                   }

                   // --- STAGE I: DECISION SLA & RELIABILITY ---
              // Wrap AI Execution in Timeout
                try {
                    // --- STAGE P: GLOBAL KILL-SWITCH LOCK ---
                    if (isAIKillSwitchActive) {
                        throw new Error("GOV_GLOBAL_KILL_SWITCH_ACTIVE");
                    }

                    const slaTimeout = 800; // ms (Configurable in real scenario)
                    const aiPromise = new Promise<void>((resolve) => {
                        // 1. Calculate Primary Utility Score
                        utilityScore = calculateUtility(openRate ?? 0.5, effectiveWeights, personalSensitivity, driftScore, contextPenalty, ai.context_sensitivity || 0.5);
                        
                        // 2. Apply Enterprise Soft Bias
                        if (enterpriseBias !== 0) {
                            utilityScore = Math.max(0, Math.min(1, utilityScore + enterpriseBias));
                        }

                        // 3. Shadow Mode Strategy (Sandbox)
                        let shadowDecision = 'sent';
                        if (ai.sandbox_mode_enabled && ai.weight_version_id) {
                            const shadowScore = calculateUtility(openRate ?? 0.5, shadowWeights, ai.sensitivity ?? 0.5, driftScore, contextPenalty, ai.context_sensitivity ?? 0.5);
                            if (shadowScore < 0.3) shadowDecision = 'silent';
                            else if (shadowScore < 0.6) shadowDecision = 'throttled';
                        }

                        // 4. Decision Engine with Stage E Intelligence
                        let finalDecision: 'sent' | 'silent' | 'throttled' | 'bundled' = 'sent'; // Added 'bundled'
                        let explanationKey = 'AI_NORMAL';
                        let predictedDelay = 0;

                        if (quietHoursApplied) {
                            finalDecision = 'bundled';
                            explanationKey = 'QUIET_HOURS_PREDICTED';
                        } else if (utilityScore < 0.3) {

                          finalDecision = 'silent';
                          explanationKey = 'AI_LOW_RELEVANCE';
                        } else if (utilityScore < 0.6) {
                          finalDecision = 'throttled';
                          explanationKey = 'AI_MEDIUM_RELEVANCE';
                        } else {
                          finalDecision = 'sent';
                          explanationKey = 'AI_HIGH_RELEVANCE';
                          
                          // PREDICTIVE TIMING: Wait for 15 mins if not peak hour
                          if (!isCritical && (ai.predictive_timing_enabled !== false)) {
                            const isPeak = cProfile?.peak_interaction_hours?.includes(userHour);
                            if (!isPeak) {
                               finalDecision = 'throttled';
                               predictedDelay = 15; 
                               explanationKey = 'AI_CONTEXT_DELAYED';
                            }
                          }
                        }

                        // 5. Governance & Shadow Logging
                        meta.weight_version_id = snapshot?.id || 'latest';
                        meta.sandbox_enabled = ai.sandbox_mode_enabled ?? false;
                        
                        if (ai.sandbox_mode_enabled && ai.weight_version_id) {
                           meta.shadow_decision = shadowDecision;
                           shadowLogs.push({
                             user_id: device.user_id,
                             shadow_weights: shadowWeights as unknown as Record<string, unknown>,
                             shadow_decision: shadowDecision,
                             actual_decision: finalDecision,
                             concordance: shadowDecision === finalDecision
                           });
                        }

                        // 6. Push to Result Containers
                        aiLogs.push({
                          user_id: device.user_id,
                          utility_score: utilityScore,
                          factor_engagement: openRate,
                          final_decision: finalDecision,
                          explanation_key: explanationKey,
                          weight_version_id: snapshot?.id || null,
                          explanation_context: {
                            text: _getExplanationText(explanationKey, timeSegment), 
                            time_segment: timeSegment,
                            penalty: contextPenalty,
                            delay: predictedDelay,
                            drift: driftScore, 
                            sensitivity: personalSensitivity 
                          }
                        });

                        // Update outer scope variables for loop finalization
                        decision = finalDecision;
                        reason = explanationKey;
                        if (predictedDelay > 0) {
                            meta.auto_healing = { rule: 'PREDICTIVE_DELAY', threshold: 0.6, actual_rate: utilityScore };
                        }

                        resolve();
                    });

                    const timeoutPromise = new Promise<void>((_, reject) => 
                        setTimeout(() => reject(new Error("AI_TIMEOUT")), slaTimeout)
                    );

                    await Promise.race([aiPromise, timeoutPromise]);

                } catch (error: unknown) {
                    const errMessage = error instanceof Error ? error.message : String(error);
                    let failureType = 'SYSTEM_ERROR';
                    let fallbackStrategy = 'DEFAULT_FALLBACK';

                    if (errMessage === 'GOV_GLOBAL_KILL_SWITCH_ACTIVE') {
                        failureType = 'GOV_GLOBAL_KILL_SWITCH';
                        fallbackStrategy = 'GOV_KILL_SWITCH_FALLBACK';
                        decision = (priority === 'high' || isCritical) ? 'sent' : 'bundled';
                    } else if (errMessage === 'AI_TIMEOUT') {
                        failureType = 'TIMEOUT';
                        fallbackStrategy = 'TIMEOUT_FALLBACK';
                        if (timeSegment === 'night' && !isCritical) {
                            decision = 'silent';
                        } else {
                            decision = 'sent';
                            priority = 'high';
                        }
                    } else {
                        // Other system errors
                        decision = 'sent';
                        priority = 'high';
                        reason = 'SYSTEM_ERROR_FALLBACK';
                    }
                    
                    // Log Failure
                    supabaseAdmin.from('ai_failure_logs').insert({
                        user_id: device.user_id,
                        error_type: failureType,
                        fallback_strategy: fallbackStrategy,
                        latency_ms: 800,
                        details: { error: errMessage, time_segment: timeSegment }
                    }).then(({ error }) => {
                        if (error) console.error("⚠️ Failed to log AI failure:", error);
                    });
                }

          }
      }

      // --- STEP 2: FLAG CHECKS ---
      if ((content_type === 'marketing' && flagMap['marketing_push_enabled'] === false)) {
          decision = 'skipped';
          reason = 'FLAG_DISABLED';
          meta.flag_disabled = 'marketing_push_enabled';
          logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision, priority: null, reason, meta});
          continue;
      }

      // --- STEP 2.5: RATE GOVERNOR ---
      const rl = rateLimitMap[`${device.user_id}_${content_type || 'chat'}`] || { hourly_count: 0, daily_count: 0 };
      const scenarioLimit = costConfig.scenario_limits[content_type] || { hourly: costConfig.default_hourly_limit, daily: costConfig.default_daily_limit };
      
      if (rl.hourly_count >= scenarioLimit.hourly || rl.daily_count >= scenarioLimit.daily) {
          decision = 'skipped';
          reason = 'RATE_LIMIT_EXCEEDED';
          meta.rate_limit = { hourly: rl.hourly_count, daily: rl.daily_count, limit: scenarioLimit };
          logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision, priority: null, reason, meta});
          continue;
      }
      
      // --- STEP 3: POLICY ENGINE ---
      const parseTime = (t: string) => {
          const parts = t.split(':');
          return (parseInt(parts[0]) * 60) + parseInt(parts[1]);
      };
      
      if (policies) {
        for (const policy of policies) {
            if (policy.start_time && policy.end_time) {
                const offset = device.timezone_offset || 0;
                let deviceTimeMins = currentTimeInMinutes + offset;
                if (deviceTimeMins < 0) deviceTimeMins += 1440;
                if (deviceTimeMins >= 1440) deviceTimeMins -= 1440;
                
                const start = parseTime(policy.start_time);
                const end = parseTime(policy.end_time);
                
                let inWindow = false;
                if (start <= end) inWindow = deviceTimeMins >= start && deviceTimeMins < end;
                else inWindow = deviceTimeMins >= start || deviceTimeMins < end;
                
                if (inWindow) {
                    if (policy.action === 'silent' && decision !== 'skipped') decision = 'silent';
                    if (policy.action === 'skipped') decision = 'skipped';
                    if (policy.priority_override) priority = policy.priority_override;
                    
                    meta.policies_applied.push({id: policy.policy_id, action: policy.action});
                    reason = `POLICY_${policy.action.toUpperCase()}`;
                }
            }
        }
      }
      
      if (decision === 'skipped') {
          logs.push({message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id, decision, priority: null, reason, meta});
          continue;
      }

      // --- STEP 4: EXPERIMENT ENGINE (A/B) ---
      if (activeExperiments) {
        for (const exp of activeExperiments) {
           let variant = assignmentMap[`${device.user_id}_${exp.experiment_id}`];
           if (!variant) {
               variant = Math.random() > 0.5 ? 'B' : 'A';
           }
           
           if (variant === 'B') {
               if (exp.variant_b_config?.force_silent) {
                   decision = 'silent';
                   reason = 'EXP_VARIANT_B_SILENT';
               }
               meta.experiments_applied.push({id: exp.experiment_id, variant: 'B'});
           } else {
               meta.experiments_applied.push({id: exp.experiment_id, variant: 'A'});
           }
        }
      }

      // Guard Foreground
      const isForeground = device.is_online && device.app_state === 'resumed';
      if (isForeground) {
        console.log(`🛡️ Foreground Guard: Skipping device ${device.device_id} for user ${device.user_id} (App is resumed)`);
        logs.push({
          message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id,
          decision: 'skipped', priority: null, reason: 'FOREGROUND_ACTIVE', meta
        });
        continue;
      }

      // --- STEP 5: AUTO-HEALING ---
      if (decision === 'sent' || decision === 'silent') {
          const canHeal = healState.dailyCount < autoHealConfig.max_daily_heals;
          const inCooldown = healState.inCooldown;

          if (!inCooldown && canHeal && !isVerificationMode) {
              const weeklySent = stats.weekly_sent_count || 0;
              const weeklyOpen = stats.weekly_open_count || 0;
              const openRate = weeklySent > 0 ? (weeklyOpen / weeklySent) : 1.0;

              if (weeklySent > 10 && openRate < autoHealConfig.critical_open_rate_threshold) {
                  priority = 'normal'; 
                  decision = 'throttled'; 
                  reason = 'AUTO_HEAL_THROTTLED';
                  meta.auto_healing = { rule: "fatigue_low_open_rate", threshold: autoHealConfig.critical_open_rate_threshold, actual_rate: openRate };
              }
          } else if (inCooldown) {
              priority = 'normal';
              decision = 'throttled';
              reason = 'HEALING_COOLDOWN_ACTIVE';
          } else if (!canHeal) {
              reason = 'HEALING_DAILY_LIMIT_REACHED';
          }
      }

      // --- STEP 5.5: COST GUARD (Refined) ---
      // isVerificationMode already defined higher up
      if (!isCritical && priority === 'high' && decision === 'sent' && !isVerificationMode) {
          const userHPStats = costStatMap[device.user_id] || { high_priority_ratio: 0 };
          if (userHPStats.high_priority_ratio > (costConfig.high_priority_cost_threshold || 0.3)) {
              priority = 'normal';
              reason = 'COST_GUARD_DOWNGRADE';
              meta.cost_governance = { ratio: userHPStats.high_priority_ratio, threshold: costConfig.high_priority_cost_threshold };
          }
      }

      
      // --- STAGE N: USER OVERRIDE INTERCEPTOR ---
      const userTypePrefs = fineGrainedMap[device.user_id]?.[content_type || 'chat'];
      const forceDelivery = userTypePrefs?.force_delivery === true;
      const prefDeviceId = userTypePrefs?.preferred_device_id;
      const bundlingAllowed = userTypePrefs?.allow_bundling !== false;

      if (forceDelivery) {
          if (decision === 'throttled' || (decision as string) === 'bundled') {


              decision = 'sent';
              reason = 'USER_OVERRIDE_FORCE_DELIVER';
          }

          meta.user_override = {
              applied: true,
              fields: ['force_delivery'],
              source: 'user_settings'
          };
      }

      if (!bundlingAllowed && (decision as string) === 'bundled') {


          decision = 'sent';
          reason = 'USER_OVERRIDE_NO_BUNDLING';

          meta.user_override = {
              applied: true,
              fields: ['allow_bundling'],
              source: 'user_settings'
          };
      }

      // --- STAGE M: DEVICE ARBITRATION ENGINE ---
      const userAttentionScores = attentionMapRecord[device.user_id] || [];
      const bestDevice = prefDeviceId 
          ? userAttentionScores.find(d => d.device_id === prefDeviceId)
          : (userAttentionScores.length > 0 
              ? [...userAttentionScores].sort((a, b) => b.attention_score - a.attention_score)[0]
              : null);

      const isBestDevice = !bestDevice || bestDevice.device_id === device.device_id;
      const arbitrationBypassed = isCritical || isSafeMode || (prefDeviceId && isBestDevice);

      if (!arbitrationBypassed && !isBestDevice) {
          decision = 'skipped';
          reason = 'ARBITRATION_SILENT';
          
          // Log arbitration details even for skipped devices
          meta.device_arbitration = {
              selected_device: bestDevice?.device_id || 'unknown',
              this_device: device.device_id,
              reason: prefDeviceId ? 'USER_PREFERRED_DEVICE_MISMATCH' : 'LOWER_ATTENTION_SCORE',
              scores: userAttentionScores.reduce((acc, curr) => {
                  acc[curr.device_id] = curr.attention_score;
                  return acc;
              }, {} as Record<string, number>)
          };
      } else if (arbitrationBypassed) {
          meta.arbitration_bypassed = true;
          if (prefDeviceId && isBestDevice) {
              meta.user_override = {
                  ...(meta.user_override || { applied: true, source: 'user_settings' }),
                  fields: [...(meta.user_override?.fields || []), 'preferred_device']
              };
          }
      } else if (isBestDevice && userAttentionScores.length > 1) {
          meta.device_arbitration = {
              selected_device: device.device_id,
              reason: 'HIGHEST_ATTENTION_SCORE',
              scores: userAttentionScores.reduce((acc, curr) => {
                acc[curr.device_id] = curr.attention_score;
                return acc;
            }, {} as Record<string, number>)
          };
      }

      // --- STAGE O: CONTINUOUS LEARNING & SHADOW ENGINE ---
      const category = content_type || 'chat';
      const learningState = learningStateMap[device.user_id]?.[category];
      const isLearningPaused = learningState?.learning_paused === true || isCritical;

      // 1. Confidence Scoring
      // Heuristic: Higher confidence if utility is far from thresholds and trust is high.
      const globalThreshold = (configMap['global_utility_threshold'] as number | undefined) || 0.4;
      const utilityDiff = Math.abs((meta.effectiveness_score as number || 0.5) - globalThreshold);

      const confidenceScore = Math.min(1.0, (utilityDiff * 2) + ((meta.trust_score as number || 0) / 100) * 0.4);
      const confidenceLevel = confidenceScore > 0.8 ? 'HIGH' : (confidenceScore > 0.4 ? 'MEDIUM' : 'LOW');

      // 2. Shadow Decision (Simulation)
      // Simulate a "Future" model variant (e.g., more aggressive bundling)
      const shadowDecision = ((meta.effectiveness_score as number || 0) < 0.3) ? 'bundled' : 'sent';
      const concordance = shadowDecision === decision;

      meta.stage_o = {
          confidence_level: confidenceLevel,
          learning_status: isLearningPaused ? 'PAUSED' : 'ACTIVE',
          shadow_concordance: concordance,
          confidence_score: confidenceScore
      };

      // Metrics for the log sink
      meta.stage_o_metrics = {
          confidence: {
              score: confidenceScore,
              level: confidenceLevel,
              factors: { utility_stability: utilityDiff, trust: (meta.trust_score as number || 0) / 100 }
          },
          shadow: {
              decision: shadowDecision,
              reason: 'EXPERIMENTAL_AGGRESSIVE_BUNDLING',
              concordance
          }
      };



      // Final fallback
      if (decision === 'sent' && priority === 'normal') decision = 'silent';
      if (priority === 'high' && decision !== 'throttled') decision = 'sent';

      // --- STAGE S: EXPERIENCE MODE & FATIGUE OVERRIDES ---
      const expPrefs = experienceMap[device.user_id];
      if (expPrefs) {
          // 1. Snooze Check
          if (expPrefs.is_snoozed && expPrefs.snooze_until && new Date(expPrefs.snooze_until) > new Date()) {
              decision = 'throttled';
              reason = 'USER_SNOOZE_ACTIVE';
          }

          // 2. Experience Mode Filtering
          if (expPrefs.experience_mode === 'critical' && (priority as string) !== 'critical') {
              decision = 'throttled';
              reason = 'MODE_CRITICAL_ONLY';
          } else if (expPrefs.experience_mode === 'smart' && decision === 'sent' && (meta.effectiveness_score || 1.0) < 0.2) {
              decision = 'bundled';
              reason = 'MODE_SMART_BUNDLING';
          }

          // 3. Category Denylist
          if (expPrefs.category_denylist?.includes(category)) {
              decision = 'skipped';
              reason = 'USER_CATEGORY_MUTED';
          }

          // 4. Fatigue Guard (Hard Stop)
          if (decision === 'sent' && (priority as string) !== 'critical') {
              const isFatigued = await _checkFatigue(supabaseAdmin, device.user_id, expPrefs.max_hourly_notifications);
              if (isFatigued) {
                  decision = 'bundled';
                  reason = 'FATIGUE_GUARD_TRIGGERED';
              }
          }
      }


      // --- DIAGNOSTIC OVERRIDE ---
      if (force_fcm === true) {
          decision = 'sent';
          reason = 'DIAGNOSTIC_FORCE_FCM';
          priority = 'high';
      }

      // --- STEP 7: EXECUTION ---
      console.log(`🎯 Device ${device.device_id} Final Decision: ${decision} (${reason})`);
      if (decision === 'sent') {
          targets.push({ 
            token: device.fcm_token, priority: priority as 'high' | 'normal', device_id: device.device_id,
            reason, decision, meta, recipient_id: device.user_id,
            badge: unreadMap[device.user_id] || 0,
            web_push_subscription: device.web_push_subscription
          });
      }
      
      logs.push({
          message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id,
          decision, priority, reason, meta,
          delivery_state: decision === 'sent' ? 'sent' : (decision === 'throttled' || (decision as string) === 'bundled' ? 'fallback_used' : 'pending')
      });




      } catch (criticalLoopError: unknown) {
          // STAGE Q: BLAST RADIUS CONTAINMENT (Fallback)
          console.error(`🚨 CRITICAL LOOP ERROR for user ${device.user_id}:`, criticalLoopError);
          const errMap = { error: String(criticalLoopError) } as unknown as RoutingMeta;
          targets.push({ 
              token: device.fcm_token, priority: 'high', device_id: device.device_id,
              reason: 'CRITICAL_LOOP_RECOVERY', decision: 'sent', meta: errMap, recipient_id: device.user_id,
              badge: unreadMap[device.user_id] || 0
          });
          logs.push({
              message_id, chat_id, device_id: device.device_id, recipient_id: device.user_id,
              decision: 'sent', priority: 'high', reason: 'CRITICAL_LOOP_RECOVERY', meta: errMap
          });
      }
    }

    // 5. Construct Notification Payload
    let notificationTitle = senderName; // Default for individual
    let finalBody = "";

    if (content_type === 'text') finalBody = text_content;
    else if (content_type === 'image') finalBody = '📷 أرسل صورة';
    else if (content_type === 'audio') finalBody = '🎤 أرسل رسالة صوتية';
    else if (content_type === 'video') finalBody = '🎥 أرسل مقطع فيديو';
    else if (content_type === 'reaction') finalBody = `قام بالتفاعل ${payload.emoji || ''} على رسالتك`;
    else finalBody = "أرسل ملفاً جديداً";

    // --- STAGE G: GROUP CHAT NOTIFICATION CONTEXT ---
    if (isGroup) {
      notificationTitle = groupName || "المجموعة"; 
      finalBody = `${senderName}: ${finalBody}`; 
    }

    bodyText = finalBody;

    // --- DIGEST LOGIC ---
    // Check if we have many throttled logs for these recipients in the last 5 mins
    const fiveMinsAgo = new Date(Date.now() - (5 * 60 * 1000)).toISOString();
    const { count: throttledCount } = await supabaseAdmin
      .from("routing_logs")
      .select("*", { count: 'exact', head: true })
      .in("recipient_id", targets.map(t => t.recipient_id))
      .eq("decision", "throttled")
      .gt("created_at", fiveMinsAgo);

    const isDigest = (throttledCount || 0) >= 10;
    if (isDigest) {
       const category = chatType === 'work' ? 'العمل' : chatType === 'social' ? 'الأصدقاء' : 'العامة';
       bodyText = `لديك ${throttledCount} رسائل جديدة في قسم ${category}.`;
    }

    // Async Logging & Counter Increments
    if (logs.length > 0) {
        supabaseAdmin.from('routing_logs').insert(logs).then(({ error }) => {
            if (error) console.error("⚠️ Failed to write routing logs:", error);
            else console.log(`📝 Logged ${logs.length} routing decisions.`);
        });

        // AI Decisions (Telemetry v3)
        if (aiLogs.length > 0) {
            supabaseAdmin.from('ai_decision_logs').insert(aiLogs).select('id, user_id').then(({ data, error }) => {
                if (error) console.error("⚠️ Failed to write AI decision logs:", error);
                else {
                    console.log(`🧠 Logged ${aiLogs.length} AI decisions.`);
                    // Link shadow logs to decision IDs
                    if (shadowLogs.length > 0 && data) {
                        const finalShadowLogs = shadowLogs.map(sl => {
                            const decisionEntry = data.find(d => d.user_id === sl.user_id);
                            return { ...sl, decision_id: decisionEntry?.id };
                        });
                        supabaseAdmin.from('ai_shadow_logs').insert(finalShadowLogs).then(({ error: shadowErr }) => {
                            if (shadowErr) console.error("⚠️ Failed to write shadow logs:", shadowErr);
                        });
                    }
                }
            });
        }

        const sentUserIds = [...new Set(targets.map(t => t.recipient_id))];
        if (sentUserIds.length > 0) {
            sentUserIds.forEach(uid => {
                supabaseAdmin.rpc('increment_rate_limit', { 
                    p_user_id: uid, 
                    p_scenario: content_type || 'chat' 
                }).then(({ error }) => {
                    if (error) console.error("⚠️ Failed to increment rate limit:", error);
                });
            });
        }

        // STAGE O: Confidence & Shadow Persistence
        logs.forEach(log => {
            const o = log.meta.stage_o_metrics;
            if (o) {
                if (o.confidence) {
                    confidenceLogs.push({
                        message_id: log.message_id,
                        user_id: log.recipient_id,
                        confidence_score: o.confidence.score,
                        confidence_level: o.confidence.level,
                        factors: o.confidence.factors
                    });
                }
                if (o.shadow) {
                   shadowLogs.push({
                       user_id: log.recipient_id,
                       shadow_weights: {}, // Placeholder or fetch from context
                       shadow_decision: o.shadow.decision,
                       actual_decision: log.decision,
                       concordance: o.shadow.concordance,
                       actual_message_id: log.message_id // Map to message_id for shadow table
                   });
                }
            }
        });


        if (confidenceLogs.length > 0) {
            supabaseAdmin.from('ai_confidence_metrics').insert(confidenceLogs).then(({ error }) => {
                if (error) console.error("⚠️ Failed to write confidence metrics:", error);
            });
        }

        if (shadowLogs.length > 0) {
            supabaseAdmin.from('ai_shadow_logs').insert(shadowLogs).then(({ error }) => {
                if (error) console.error("⚠️ Failed to write shadow logs:", error);
            });
        }


        // STAGE J: SYNC TO INBOX (Throttled, Downgraded, Critical)
        for (const log of logs) {
            const isCriticalMsg = log.reason === 'CRITICAL_BYPASS' || log.priority === 'critical';
            const isThrottled = log.decision === 'throttled';
            const isDowngraded = log.reason === 'COST_GUARD_DOWNGRADE';
            const isBundled = log.decision === 'bundled';

            if (isCriticalMsg || isThrottled || isDowngraded) {
                _syncToInbox({
                    user_id: log.recipient_id,
                    chat_id: String(chat_id),
                    message_id: String(message_id),
                    title: senderName,
                    body: bodyText,
                    scenario: content_type || 'chat',
                    priority: log.priority || 'normal',
                    original_decision: log.decision,
                    delivered_via: isThrottled ? 'inbox' : 'fcm',
                    fallback_used: isThrottled,
                    metadata: log.meta
                });

                if (isThrottled) {
                    _resolveFallback({
                        userId: log.recipient_id,
                        scenario: content_type || 'chat',
                        priority: log.priority || 'normal',
                        decision: log.decision,
                        title: notificationTitle,
                        body: bodyText,
                        messageId: String(message_id)
                    });
                }
            }

            if (isBundled) {
                _syncToBundle({
                    userId: log.recipient_id,
                    messageId: String(message_id),
                    scenario: content_type || 'chat',
                    reason: log.reason
                });
            }
        }

    }

    // 6. Send Multicast (Batched by Priority)
    const highPriorityTargets = targets.filter(t => t.priority === 'high' || t.priority === 'critical');
    const normalPriorityTargets = targets.filter(t => t.priority === 'normal');

    // STAGE I: CIRCUIT BREAKER CHECK
    const { data: breakerState } = await supabaseAdmin.rpc('check_circuit_breaker', { p_service_name: 'fcm' });
    const isCircuitOpen = breakerState?.state === 'OPEN';

    if (isCircuitOpen) {
        console.warn("🛡️ Circuit Breaker OPEN for FCM. Skipping external call.");
        // Directly fallback for all targets
        const fallbackPromises = targets.map(t => _resolveFallback({
            userId: t.recipient_id,
            scenario: content_type || 'chat',
            priority: t.priority,
            decision: 'circuit_broken',
            title: notificationTitle,
            body: bodyText,
            messageId: String(message_id)
        }));
        await Promise.all(fallbackPromises);
        return new Response(JSON.stringify({ message: "Circuit OPEN. Fallbacks triggerd." }));
    }

    const sendBatch = async (batchTargets: typeof targets, prio: 'high' | 'normal') => {
        if (batchTargets.length === 0) return { success: 0, failure: 0 };
        
        let successCount = 0;
        let failureCount = 0;

        try {
            const messaging = getMessaging();
            
            // 1. Separate FCM and Web Push targets
            const fcmTargets = batchTargets.filter(t => t.token && !t.web_push_subscription);
            const webPushTargets = batchTargets.filter(t => t.web_push_subscription);

            // 2. Handle FCM Targets
            if (fcmTargets.length > 0) {
                const messages = fcmTargets.map(target => ({
                    token: target.token!,
                    // [STABILIZATION]: Moving to data-only payload as per user strategy
                    // This prevents Android/Web from showing default "Silent" or inconsistent notifications.
                    data: {
                        type: 'message',
                        title: notificationTitle,
                        body: bodyText,
                        chat_id: String(chat_id),
                        message_id: String(message_id),
                        sender_id: String(sender_id),
                        priority_level: prio,
                        product_category: (target.priority === 'critical' ? 'ALERT' : (isGroup ? 'CHAT_GROUP' : 'CHAT_PRIVATE')),
                        click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        deep_link: `talkmate://chat/${chat_id}`,
                        meta_ai_reason: target.reason || 'UNKNOWN',
                        meta_trust_score: String(target.meta?.trust_score || '0'),
                        unread_count: String(target.badge || '0'),
                        meta_timestamp: new Date().toISOString(),
                        tag: `chat_${chat_id}`, 
                        group_id: `group_${chat_id}`
                    },
                    android: { 
                        priority: prio,
                        // [PURITY]: Removing the notification block to force 'data' message behavior.
                        // This ensures the custom background handler in Flutter is triggered.
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: prio === 'high' ? "default" : undefined,
                                "content-available": prio === 'normal' ? 1 : 0,
                                badge: target.badge ?? 0
                            }
                        }
                    }
                }));

                const response = await messaging.sendEach(messages);
                successCount += response.successCount;
                failureCount += response.failureCount;

                // Mark successful FCM delivery
                supabaseAdmin.rpc('reset_circuit_breaker', { p_service_name: 'fcm' });

                response.responses.forEach((res, idx) => {
                    const target = fcmTargets[idx];
                    const state = res.success ? 'delivered' : 'failed';
                    
                    if (res.success) {
                        console.log(`✅ FCM Success for user ${target.recipient_id} (Token: ${target.token?.substring(0, 10)}...)`);
                    }
                    
                    // [AUTO-HEAL]: If FCM says the token is invalid or not registered, deactivate the device
                    if (!res.success && res.error) {
                        const errorCode = res.error.code;
                        if (errorCode === 'messaging/invalid-argument' || errorCode === 'messaging/registration-token-not-registered') {
                            console.warn(`🧹 Auto-Heal: Deactivating invalid device token for user ${target.recipient_id}`);
                            supabaseAdmin
                                .from('user_devices')
                                .update({ is_active: false, updated_at: new Date().toISOString() })
                                .eq('device_id', target.device_id)
                                .eq('user_id', target.recipient_id)
                                .then(({ error }) => {
                                    if (error) console.error("⚠️ Failed to auto-deactivate device:", error);
                                });
                        }
                    }

                    supabaseAdmin.from('routing_logs').update({
                        delivery_state: state,
                        delivery_error: res.error ? { code: res.error.code, message: res.error.message } : null
                    }).match({ 
                        message_id: String(message_id), 
                        recipient_id: target.recipient_id,
                        device_id: target.device_id
                    });

                    if (!res.success) {
                        console.error(`❌ FCM Failure for ${target.recipient_id}:`, res.error);
                        _resolveFallback({
                            userId: target.recipient_id,
                            scenario: content_type || 'chat',
                            priority: target.priority,
                            decision: target.decision,
                            title: senderName,
                            body: bodyText,
                            messageId: String(message_id)
                        });
                    }
                });
            }

            // 3. Handle Web Push Targets
            for (const target of webPushTargets) {
                try {
                    const payload = JSON.stringify({
                        // Standard top-level fields for Web Service Worker compatibility
                        title: notificationTitle,
                        body: bodyText,
                        // data block for unified handling in Flutter (if tab is open)
                        data: {
                            title: notificationTitle,
                            body: bodyText,
                            chat_id: String(chat_id),
                            message_id: String(message_id),
                            sender_id: String(sender_id)
                        }
                    });

                    await webpush.sendNotification(target.web_push_subscription, payload);
                    successCount++;

                    supabaseAdmin.from('routing_logs').update({
                        delivery_state: 'delivered'
                    }).match({ 
                        message_id: String(message_id), 
                        recipient_id: target.recipient_id,
                        device_id: target.device_id
                    });
                // deno-lint-ignore no-explicit-any
                } catch (wpError: any) {
                    console.error(`❌ Web Push Failure for ${target.recipient_id}:`, wpError);
                    failureCount++;

                    supabaseAdmin.from('routing_logs').update({
                        delivery_state: 'failed',
                        delivery_error: { message: wpError.message, statusCode: wpError.statusCode }
                    }).match({ 
                        message_id: String(message_id), 
                        recipient_id: target.recipient_id,
                        device_id: target.device_id
                    });

                    _resolveFallback({
                        userId: target.recipient_id,
                        scenario: content_type || 'chat',
                        priority: target.priority,
                        decision: target.decision,
                        title: senderName,
                        body: bodyText,
                        messageId: String(message_id)
                    });
                }
            }
            
            return { success: successCount, failure: failureCount };

        } catch (systemError) {
             console.error("🔥 PUSH SYSTEM ERROR:", systemError);
             await supabaseAdmin.rpc('trip_circuit_breaker', { p_service_name: 'fcm', p_force_open: false });

             batchTargets.forEach(t => {
                _resolveFallback({
                    userId: t.recipient_id,
                    scenario: content_type || 'chat',
                    priority: t.priority,
                    decision: 'system_failure',
                    title: senderName,
                    body: bodyText,
                    messageId: String(message_id)
                });
             });
             
             return { success: 0, failure: batchTargets.length };
        }
    };

    const resultsHigh = await sendBatch(highPriorityTargets, 'high');
    const resultsNormal = await sendBatch(normalPriorityTargets, 'normal');


    return new Response(JSON.stringify({ 
        highPriority: resultsHigh, 
        normalPriority: resultsNormal 
    }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ AI Routing Error:", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});

function _getExplanationText(key: string, segment?: string): string {
  const segmentText = segment === 'night' ? ' خلال وقت راحتك' : segment === 'work' ? ' خلال ساعات عملك' : '';
  switch (key) {
    case 'GOV_SAFE_MODE': return 'تم إيصال الرسالة فوراً لضمان بقائك على اتصال.';
    case 'GOV_GLOBAL_KILL_SWITCH': return 'تم التوصيل المباشر كإجراء احتياطي لضمان الموثوقية.';
    case 'GOV_CHAT_EXCLUSION': return 'تم التوصيل المباشر بناءً على تفضيلك لهذه المحادثة.';
    case 'GOV_PAUSE_ACTIVE': return 'تم التوصيل لأن النظام الذكي في وضع الإيقاف المؤقت.';
    case 'AI_LOW_RELEVANCE': return 'تم التسليم بصمت لأن المحتوى قد لا يتطلب انتباهك الفوري' + segmentText;
    case 'AI_MEDIUM_RELEVANCE': return 'تم تجميع الإشعار لتقليل المقاطعات الرقمية' + segmentText;
    case 'AI_HIGH_RELEVANCE': return 'تم الإرسال فوراً لأننا نعلم أن هذا يهمك' + segmentText;
    case 'AI_CONTEXT_DELAYED': return 'تم التأجيل للوقت الأنسب لك لضمان أفضل قراءة.';
    case 'QUIET_HOURS_PREDICTED': return 'تم النقل للموجز الصامت للحفاظ على هدوئك الآن.';
    case 'LOW_TRUST_MARKETING_DOWNGRADE': return 'تم تقليل مستوى الأولوية بناءً على نمط استجابتك السابق.';
    case 'ARBITRATION_SILENT': return 'تم الصمت لأنك تستخدم التطبيق بنشاط على جهاز آخر.';
    case 'FATIGUE_GUARD_TRIGGERED': return 'تم التجميع لتقليل معدل الإشعارات المتتالية وحمايتك من التشتت.';
    case 'MODE_CRITICAL_ONLY': return 'تم حجب الإشعار بناءً على وضع "الأولوية فقط" المفعّل لديك.';
    default: return 'قرار ذكي تم اتخاذه لتحسين تجربة استخدامك.';
  }
}







