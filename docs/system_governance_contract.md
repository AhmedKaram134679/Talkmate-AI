# TalkMate AI - System Governance & Trust Contract (Golden Baseline)

> [!IMPORTANT]
> **ARCHITECTURAL HARD FREEZE (Effective: 2026-01-10)** This system is now in
> "Engineering Lock". Any deviation from the routing logic or AI decision layers
> defined in Stage S is strictly prohibited without Release Authority approval.

This document serves as the official technical and ethical "Contract" for the
intelligent notification system. It defines the hard boundaries, architectural
decisions, and emergency procedures that govern the AI's behavior.

## 1. Architecture Decision Records (ADR) - Stage S Final

### ADR-001: User Override Supremacy

- **Status**: Accepted & Locked
- **Decision**: User settings (Fine-grained preferences, force delivery) always
  execute _after_ AI routing and _must_ override any AI decision
  (sent/silent/throttled).

### ADR-002: Graceful Degradation (Global Kill-Switch)

- **Status**: Accepted & Locked
- **Decision**: A global `ai_global_kill_switch` in `system_governance` table
  immediately routes all messages using strict rule-based logic (High -> Sent,
  Normal -> Bundled).

### ADR-003: Non-Intrusive Learning Guardrails

- **Status**: Accepted & Locked
- **Decision**: Learning is automatically paused for critical messages, users
  with frequent overrides, and low-confidence decisions.

### ADR-004: Stage S - Experience & Fatigue Guard

- **Status**: Accepted & Locked
- **Decision**: Implementation of a deterministic "Fatigue Guard" that throttles
  non-critical notifications once density thresholds are reached, regardless of
  AI effectiveness scores.
- **Enforcement**: Processed via `fn_is_user_fatigued` RPC.

## 2. Freeze Enforcement (The "Engineering Lock")

The following layers are **FROZEN**. Changes are limited to UI text, Feature
Flags, and JWT parameters:

1. **Routing Logic**: `push-handler/index.ts` routing core.
2. **AI Decision Layers**: Utility calculation and Trust Score integration.
3. **Trust Score Engine**: Decay and acceleration algorithms.
4. **Fatigue Guard**: MAX_DENSITY thresholds and RPC triggers.
5. **Bundling Logic**: Cross-platform grouping tags.

## 3. Learning Boundaries (The "Never List")

**The AI will NEVER:**

1. **Block Critical Alerts**: Call notifications and @mentions are exempt from
   AI silence.
2. **Learn from Overrides**: Overridden decisions are used to _pause_ learning.
3. **Execute Low Confidence Actions**: SAFE DEFAULT execution for scores < 0.4.
4. **Access Message Content**: Metadata-only processing for privacy.

## 4. Emergency Procedures

### Emergency AI Disable (Global)

Run SQL to stop all AI involvement:

```sql
UPDATE public.system_governance 
SET value = '{"enabled": true}' -- Set to true to ACTIVATE the kill-switch
WHERE key = 'ai_global_kill_switch';
```

### Manual Audit Trail

All decisions are logged in `routing_logs`. Internal audit views must monitor
`is_silent` and `delivery_state`.

## 5. Exit Criteria & Release Authority

The system is considered **Production Ready (Stage S)**.

- **Dart Integrity**: Checked (`flutter analyze` - Clean).
- **Edge Integrity**: Checked (`supabase deploy` - Success).
- **Governance**: DEFAULT TO FALLBACK is active.
