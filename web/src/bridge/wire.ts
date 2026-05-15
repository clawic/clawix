/**
 * Zod schemas mirroring `packages/ClawixCore/Sources/ClawixCore/BridgeModels.swift`.
 * Field names and optionality must match. CI script `scripts/check-wire-parity.ts`
 * compares this file against the Swift source on every build.
 */

import { z } from "zod";

/** ISO-8601 date string from the Swift JSONEncoder. */
export const ZIso8601 = z.string().datetime({ offset: true });

export const ZWireRole = z.enum(["user", "assistant"]);
export type WireRole = z.infer<typeof ZWireRole>;

export const ZWireAttachmentKind = z.enum(["image", "audio"]);
export type WireAttachmentKind = z.infer<typeof ZWireAttachmentKind>;

export const ZWireAttachment = z.object({
  id: z.string(),
  kind: ZWireAttachmentKind.default("image"),
  mimeType: z.string(),
  filename: z.string().optional(),
  dataBase64: z.string(),
});
export type WireAttachment = z.infer<typeof ZWireAttachment>;

export const ZWireProject = z.object({
  id: z.string(),
  title: z.string(),
  cwd: z.string(),
  hasGitRepo: z.boolean().default(false),
  branch: z.string().optional(),
  lastUsedAt: ZIso8601.optional(),
});
export type WireProject = z.infer<typeof ZWireProject>;

export const ZWireSession = z.object({
  id: z.string(),
  title: z.string(),
  createdAt: ZIso8601,
  isPinned: z.boolean().default(false),
  isArchived: z.boolean().default(false),
  hasActiveTurn: z.boolean().default(false),
  lastMessageAt: ZIso8601.optional(),
  lastMessagePreview: z.string().optional(),
  branch: z.string().optional(),
  cwd: z.string().optional(),
  lastTurnInterrupted: z.boolean().default(false),
  threadId: z.string().optional(),
  agent: z.string().default("codex"),
  agentId: z.string().optional(),
});
export type WireSession = z.infer<typeof ZWireSession>;

export const ZWireWorkItemStatus = z.enum(["inProgress", "completed", "failed"]);
export type WireWorkItemStatus = z.infer<typeof ZWireWorkItemStatus>;

/** Discriminator string mirroring `WorkItemKind` in Swift. */
export const ZWireWorkItem = z.object({
  id: z.string(),
  /** "command" | "fileChange" | "webSearch" | "mcpTool" | "dynamicTool" | "imageGeneration" | "imageView" */
  kind: z.string(),
  status: ZWireWorkItemStatus,
  commandText: z.string().optional(),
  /** "read" | "listFiles" | "search" | "unknown" */
  commandActions: z.array(z.string()).optional(),
  paths: z.array(z.string()).optional(),
  mcpServer: z.string().optional(),
  mcpTool: z.string().optional(),
  dynamicToolName: z.string().optional(),
  generatedImagePath: z.string().optional(),
});
export type WireWorkItem = z.infer<typeof ZWireWorkItem>;

export const ZWireTimelineEntry = z.discriminatedUnion("type", [
  z.object({ type: z.literal("reasoning"), id: z.string(), text: z.string() }),
  z.object({ type: z.literal("message"), id: z.string(), text: z.string() }),
  z.object({ type: z.literal("tools"), id: z.string(), items: z.array(ZWireWorkItem) }),
]);
export type WireTimelineEntry = z.infer<typeof ZWireTimelineEntry>;

export const ZWireWorkSummary = z.object({
  startedAt: ZIso8601,
  endedAt: ZIso8601.optional(),
  items: z.array(ZWireWorkItem),
});
export type WireWorkSummary = z.infer<typeof ZWireWorkSummary>;

export const ZWireAudioRef = z.object({
  id: z.string(),
  mimeType: z.string(),
  durationMs: z.number().int(),
});
export type WireAudioRef = z.infer<typeof ZWireAudioRef>;

export const ZWireAudioKind = z.enum(["user_message", "dictation", "agent_tts"]);
export type WireAudioKind = z.infer<typeof ZWireAudioKind>;

export const ZWireAudioOriginActor = z.enum(["user", "agent"]);
export type WireAudioOriginActor = z.infer<typeof ZWireAudioOriginActor>;

export const ZWireAudioTranscriptRole = z.enum(["transcription", "synthesis_source"]);
export type WireAudioTranscriptRole = z.infer<typeof ZWireAudioTranscriptRole>;

export const ZWireAudioTranscript = z.object({
  id: z.string(),
  audioId: z.string(),
  role: ZWireAudioTranscriptRole,
  text: z.string(),
  provider: z.string().nullable().optional(),
  language: z.string().nullable().optional(),
  createdAt: z.number().int(),
  isPrimary: z.boolean(),
});
export type WireAudioTranscript = z.infer<typeof ZWireAudioTranscript>;

export const ZWireAudioAsset = z.object({
  id: z.string(),
  kind: ZWireAudioKind,
  appId: z.string(),
  originActor: ZWireAudioOriginActor,
  mimeType: z.string(),
  bytesRelPath: z.string(),
  durationMs: z.number().int(),
  createdAt: z.number().int(),
  deviceId: z.string().nullable().optional(),
  sessionId: z.string().nullable().optional(),
  threadId: z.string().nullable().optional(),
  linkedMessageId: z.string().nullable().optional(),
  metadataJson: z.string().nullable().optional(),
});
export type WireAudioAsset = z.infer<typeof ZWireAudioAsset>;

export const ZWireAudioAssetWithTranscripts = z.object({
  asset: ZWireAudioAsset,
  transcripts: z.array(ZWireAudioTranscript),
});
export type WireAudioAssetWithTranscripts = z.infer<typeof ZWireAudioAssetWithTranscripts>;

export const ZWireAudioRegisterTranscript = z.object({
  text: z.string(),
  role: ZWireAudioTranscriptRole.nullable().optional(),
  provider: z.string().nullable().optional(),
  language: z.string().nullable().optional(),
});
export type WireAudioRegisterTranscript = z.infer<typeof ZWireAudioRegisterTranscript>;

export const ZWireAudioRegisterRequest = z.object({
  id: z.string().nullable().optional(),
  kind: ZWireAudioKind,
  appId: z.string(),
  originActor: ZWireAudioOriginActor,
  mimeType: z.string(),
  bytesBase64: z.string(),
  durationMs: z.number().int(),
  deviceId: z.string().nullable().optional(),
  sessionId: z.string().nullable().optional(),
  threadId: z.string().nullable().optional(),
  linkedMessageId: z.string().nullable().optional(),
  metadataJson: z.string().nullable().optional(),
  transcript: ZWireAudioRegisterTranscript.nullable().optional(),
});
export type WireAudioRegisterRequest = z.infer<typeof ZWireAudioRegisterRequest>;

export const ZWireAudioAttachTranscriptInput = z.object({
  text: z.string(),
  role: ZWireAudioTranscriptRole,
  provider: z.string().nullable().optional(),
  language: z.string().nullable().optional(),
  markAsPrimary: z.boolean().nullable().optional(),
});
export type WireAudioAttachTranscriptInput = z.infer<typeof ZWireAudioAttachTranscriptInput>;

export const ZWireAudioListFilter = z.object({
  appId: z.string(),
  kind: ZWireAudioKind.nullable().optional(),
  originActor: ZWireAudioOriginActor.nullable().optional(),
  deviceId: z.string().nullable().optional(),
  sessionId: z.string().nullable().optional(),
  threadId: z.string().nullable().optional(),
  linkedMessageId: z.string().nullable().optional(),
  fromCreatedAt: z.number().int().nullable().optional(),
  toCreatedAt: z.number().int().nullable().optional(),
  limit: z.number().int().nullable().optional(),
  offset: z.number().int().nullable().optional(),
});
export type WireAudioListFilter = z.infer<typeof ZWireAudioListFilter>;

export const ZWireAudioListResult = z.object({
  items: z.array(ZWireAudioAssetWithTranscripts),
  total: z.number().int(),
});
export type WireAudioListResult = z.infer<typeof ZWireAudioListResult>;

export const ZWireMessage = z.object({
  id: z.string(),
  role: ZWireRole,
  content: z.string(),
  reasoningText: z.string().default(""),
  streamingFinished: z.boolean().default(true),
  isError: z.boolean().default(false),
  timestamp: ZIso8601,
  timeline: z.array(ZWireTimelineEntry).default([]),
  workSummary: ZWireWorkSummary.optional(),
  audioRef: ZWireAudioRef.optional(),
  attachments: z.array(ZWireAttachment).default([]),
});
export type WireMessage = z.infer<typeof ZWireMessage>;

export const ZWireRateLimitWindow = z.object({
  usedPercent: z.number().int(),
  resetsAt: z.number().int().nullable().optional(),
  windowDurationMins: z.number().int().nullable().optional(),
});
export type WireRateLimitWindow = z.infer<typeof ZWireRateLimitWindow>;

export const ZWireCreditsSnapshot = z.object({
  hasCredits: z.boolean(),
  unlimited: z.boolean(),
  balance: z.string().nullable().optional(),
});
export type WireCreditsSnapshot = z.infer<typeof ZWireCreditsSnapshot>;

export const ZWireRateLimitSnapshot = z.object({
  primary: ZWireRateLimitWindow.nullable().optional(),
  secondary: ZWireRateLimitWindow.nullable().optional(),
  credits: ZWireCreditsSnapshot.nullable().optional(),
  limitId: z.string().nullable().optional(),
  limitName: z.string().nullable().optional(),
});
export type WireRateLimitSnapshot = z.infer<typeof ZWireRateLimitSnapshot>;
