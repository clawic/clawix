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

export const ZWireChat = z.object({
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
});
export type WireChat = z.infer<typeof ZWireChat>;

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
