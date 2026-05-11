/**
 * Discriminated union of all bridge frame bodies.
 * Mirrors `BridgeBody` in `packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift`.
 *
 * Wire format is FLAT: every frame is a top-level JSON object with
 * `schemaVersion`, `type`, and the payload fields. There is no `payload` envelope.
 */

import { z } from "zod";
import {
  ZWireAttachment,
  ZWireAudioAssetWithTranscripts,
  ZWireAudioAttachTranscriptInput,
  ZWireAudioListFilter,
  ZWireAudioListResult,
  ZWireAudioRegisterRequest,
  ZWireAudioTranscript,
  ZWireChat,
  ZWireMessage,
  ZWireProject,
  ZWireRateLimitSnapshot,
} from "./wire";

export const BRIDGE_SCHEMA_VERSION = 5 as const;
export const BRIDGE_INITIAL_PAGE_LIMIT = 60 as const;
export const BRIDGE_OLDER_PAGE_LIMIT = 40 as const;

export const ZClientKind = z.enum(["ios", "desktop"]);
export type ClientKind = z.infer<typeof ZClientKind>;

const base = { schemaVersion: z.number().int().default(BRIDGE_SCHEMA_VERSION) };

/** Outbound: client -> server */
export const ZAuth = z.object({
  ...base,
  type: z.literal("auth"),
  token: z.string(),
  deviceName: z.string().optional(),
  clientKind: ZClientKind.optional(),
});

export const ZListChats = z.object({ ...base, type: z.literal("listChats") });

export const ZOpenChat = z.object({
  ...base,
  type: z.literal("openChat"),
  chatId: z.string(),
  limit: z.number().int().optional(),
});

export const ZLoadOlderMessages = z.object({
  ...base,
  type: z.literal("loadOlderMessages"),
  chatId: z.string(),
  beforeMessageId: z.string(),
  limit: z.number().int(),
});

export const ZSendPrompt = z.object({
  ...base,
  type: z.literal("sendPrompt"),
  chatId: z.string(),
  text: z.string(),
  attachments: z.array(ZWireAttachment).optional().default([]),
});

export const ZNewChat = z.object({
  ...base,
  type: z.literal("newChat"),
  chatId: z.string(),
  text: z.string(),
  attachments: z.array(ZWireAttachment).optional().default([]),
});

export const ZInterruptTurn = z.object({ ...base, type: z.literal("interruptTurn"), chatId: z.string() });

export const ZEditPrompt = z.object({
  ...base,
  type: z.literal("editPrompt"),
  chatId: z.string(),
  messageId: z.string(),
  text: z.string(),
});

export const ZArchiveChat = z.object({ ...base, type: z.literal("archiveChat"), chatId: z.string() });
export const ZUnarchiveChat = z.object({ ...base, type: z.literal("unarchiveChat"), chatId: z.string() });
export const ZPinChat = z.object({ ...base, type: z.literal("pinChat"), chatId: z.string() });
export const ZUnpinChat = z.object({ ...base, type: z.literal("unpinChat"), chatId: z.string() });
export const ZRenameChat = z.object({ ...base, type: z.literal("renameChat"), chatId: z.string(), title: z.string() });
export const ZPairingStart = z.object({ ...base, type: z.literal("pairingStart") });
export const ZListProjects = z.object({ ...base, type: z.literal("listProjects") });
export const ZReadFile = z.object({ ...base, type: z.literal("readFile"), path: z.string() });

export const ZTranscribeAudio = z.object({
  ...base,
  type: z.literal("transcribeAudio"),
  requestId: z.string(),
  audioBase64: z.string(),
  mimeType: z.string(),
  language: z.string().optional(),
});
export const ZRequestAudio = z.object({ ...base, type: z.literal("requestAudio"), audioId: z.string() });
export const ZRequestGeneratedImage = z.object({ ...base, type: z.literal("requestGeneratedImage"), path: z.string() });
export const ZRequestRateLimits = z.object({ ...base, type: z.literal("requestRateLimits") });

/** Inbound: server -> client */
export const ZAuthOk = z.object({ ...base, type: z.literal("authOk"), macName: z.string().optional() });
export const ZAuthFailed = z.object({ ...base, type: z.literal("authFailed"), reason: z.string() });
export const ZVersionMismatch = z.object({ ...base, type: z.literal("versionMismatch"), serverVersion: z.number().int() });

export const ZChatsSnapshot = z.object({ ...base, type: z.literal("chatsSnapshot"), chats: z.array(ZWireChat) });
export const ZChatUpdated = z.object({ ...base, type: z.literal("chatUpdated"), chat: ZWireChat });

export const ZMessagesSnapshot = z.object({
  ...base,
  type: z.literal("messagesSnapshot"),
  chatId: z.string(),
  messages: z.array(ZWireMessage),
  hasMore: z.boolean().optional(),
});

export const ZMessagesPage = z.object({
  ...base,
  type: z.literal("messagesPage"),
  chatId: z.string(),
  messages: z.array(ZWireMessage),
  hasMore: z.boolean(),
});

export const ZMessageAppended = z.object({
  ...base,
  type: z.literal("messageAppended"),
  chatId: z.string(),
  message: ZWireMessage,
});

export const ZMessageStreaming = z.object({
  ...base,
  type: z.literal("messageStreaming"),
  chatId: z.string(),
  messageId: z.string(),
  content: z.string(),
  reasoningText: z.string(),
  finished: z.boolean(),
});

export const ZErrorEvent = z.object({ ...base, type: z.literal("errorEvent"), code: z.string(), message: z.string() });

export const ZPairingPayload = z.object({
  ...base,
  type: z.literal("pairingPayload"),
  qrJson: z.string(),
  bearer: z.string(),
});

export const ZProjectsSnapshot = z.object({
  ...base,
  type: z.literal("projectsSnapshot"),
  projects: z.array(ZWireProject),
});

export const ZFileSnapshot = z.object({
  ...base,
  type: z.literal("fileSnapshot"),
  path: z.string(),
  content: z.string().optional(),
  isMarkdown: z.boolean().default(false),
  error: z.string().optional(),
});

export const ZTranscriptionResult = z.object({
  ...base,
  type: z.literal("transcriptionResult"),
  requestId: z.string(),
  text: z.string(),
  errorMessage: z.string().optional(),
});

export const ZAudioSnapshot = z.object({
  ...base,
  type: z.literal("audioSnapshot"),
  audioId: z.string(),
  audioBase64: z.string().optional(),
  mimeType: z.string().optional(),
  errorMessage: z.string().optional(),
});

export const ZGeneratedImageSnapshot = z.object({
  ...base,
  type: z.literal("generatedImageSnapshot"),
  path: z.string(),
  dataBase64: z.string().optional(),
  mimeType: z.string().optional(),
  errorMessage: z.string().optional(),
});

export const ZBridgeState = z.object({
  ...base,
  type: z.literal("bridgeState"),
  state: z.string(),
  chatCount: z.number().int(),
  message: z.string().optional(),
});

export const ZRateLimitsPayload = z.object({
  rateLimits: ZWireRateLimitSnapshot.nullable().optional(),
  rateLimitsByLimitId: z.record(z.string(), ZWireRateLimitSnapshot).default({}),
});

export const ZRateLimitsSnapshot = z.object({
  ...base,
  type: z.literal("rateLimitsSnapshot"),
  ...ZRateLimitsPayload.shape,
});

export const ZRateLimitsUpdated = z.object({
  ...base,
  type: z.literal("rateLimitsUpdated"),
  ...ZRateLimitsPayload.shape,
});

// v7 audio catalog frames (outbound: client -> daemon).
export const ZAudioRegister = z.object({
  ...base,
  type: z.literal("audioRegister"),
  requestId: z.string(),
  request: ZWireAudioRegisterRequest,
});
export const ZAudioAttachTranscript = z.object({
  ...base,
  type: z.literal("audioAttachTranscript"),
  requestId: z.string(),
  audioId: z.string(),
  transcript: ZWireAudioAttachTranscriptInput,
});
export const ZAudioGet = z.object({
  ...base,
  type: z.literal("audioGet"),
  requestId: z.string(),
  audioId: z.string(),
  appId: z.string(),
});
export const ZAudioGetBytes = z.object({
  ...base,
  type: z.literal("audioGetBytes"),
  requestId: z.string(),
  audioId: z.string(),
  appId: z.string(),
});
export const ZAudioList = z.object({
  ...base,
  type: z.literal("audioList"),
  requestId: z.string(),
  filter: ZWireAudioListFilter,
});
export const ZAudioDelete = z.object({
  ...base,
  type: z.literal("audioDelete"),
  requestId: z.string(),
  audioId: z.string(),
  appId: z.string(),
});

// v7 audio catalog frames (inbound: daemon -> client).
export const ZAudioRegisterResult = z.object({
  ...base,
  type: z.literal("audioRegisterResult"),
  requestId: z.string(),
  asset: ZWireAudioAssetWithTranscripts.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioAttachTranscriptResult = z.object({
  ...base,
  type: z.literal("audioAttachTranscriptResult"),
  requestId: z.string(),
  transcript: ZWireAudioTranscript.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioGetResult = z.object({
  ...base,
  type: z.literal("audioGetResult"),
  requestId: z.string(),
  asset: ZWireAudioAssetWithTranscripts.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioBytesResult = z.object({
  ...base,
  type: z.literal("audioBytesResult"),
  requestId: z.string(),
  audioBase64: z.string().nullable().optional(),
  mimeType: z.string().nullable().optional(),
  durationMs: z.number().int().nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioListResult = z.object({
  ...base,
  type: z.literal("audioListResult"),
  requestId: z.string(),
  list: ZWireAudioListResult.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioDeleteResult = z.object({
  ...base,
  type: z.literal("audioDeleteResult"),
  requestId: z.string(),
  deleted: z.boolean(),
  errorMessage: z.string().nullable().optional(),
});

/** Full discriminated union covering both directions. */
export const ZBridgeFrame = z.discriminatedUnion("type", [
  ZAuth,
  ZListChats,
  ZOpenChat,
  ZLoadOlderMessages,
  ZSendPrompt,
  ZNewChat,
  ZInterruptTurn,
  ZEditPrompt,
  ZArchiveChat,
  ZUnarchiveChat,
  ZPinChat,
  ZUnpinChat,
  ZRenameChat,
  ZPairingStart,
  ZListProjects,
  ZReadFile,
  ZTranscribeAudio,
  ZRequestAudio,
  ZRequestGeneratedImage,
  ZRequestRateLimits,
  ZAuthOk,
  ZAuthFailed,
  ZVersionMismatch,
  ZChatsSnapshot,
  ZChatUpdated,
  ZMessagesSnapshot,
  ZMessagesPage,
  ZMessageAppended,
  ZMessageStreaming,
  ZErrorEvent,
  ZPairingPayload,
  ZProjectsSnapshot,
  ZFileSnapshot,
  ZTranscriptionResult,
  ZAudioSnapshot,
  ZGeneratedImageSnapshot,
  ZBridgeState,
  ZRateLimitsSnapshot,
  ZRateLimitsUpdated,
  ZAudioRegister,
  ZAudioAttachTranscript,
  ZAudioGet,
  ZAudioGetBytes,
  ZAudioList,
  ZAudioDelete,
  ZAudioRegisterResult,
  ZAudioAttachTranscriptResult,
  ZAudioGetResult,
  ZAudioBytesResult,
  ZAudioListResult,
  ZAudioDeleteResult,
]);

export type BridgeFrame = z.infer<typeof ZBridgeFrame>;
export type FrameType = BridgeFrame["type"];

export type FrameOf<T extends FrameType> = Extract<BridgeFrame, { type: T }>;

/** Distributive Omit so each member of the union keeps its own type tag. */
type DistributiveOmit<T, K extends keyof T> = T extends unknown ? Omit<T, K> : never;
export type FrameBody = DistributiveOmit<BridgeFrame, "schemaVersion">;

/** Encode a frame body to a JSON string ready to send over WebSocket. */
export function encodeFrame(body: FrameBody): string {
  const frame = { schemaVersion: BRIDGE_SCHEMA_VERSION, ...body };
  return JSON.stringify(frame);
}

/**
 * Decode a JSON text frame received over WebSocket.
 * Returns `null` if the type is unknown (forward compatibility: old web client
 * receiving v6 frames). The caller decides whether to surface "Update Clawix".
 */
export function decodeFrame(raw: string): BridgeFrame | null {
  try {
    const obj = JSON.parse(raw);
    const result = ZBridgeFrame.safeParse(obj);
    if (result.success) {
      return result.data;
    }
    return null;
  } catch {
    return null;
  }
}

/** Inspect schemaVersion before full parsing to bail on mismatched peers. */
export function peekSchemaVersion(raw: string): number | null {
  try {
    const obj = JSON.parse(raw);
    if (typeof obj === "object" && obj !== null && typeof obj.schemaVersion === "number") {
      return obj.schemaVersion;
    }
    return null;
  } catch {
    return null;
  }
}

/** QR JSON payload from the daemon: shape declared in PairingService.swift */
export const ZQrPayload = z.object({
  v: z.number().int(),
  host: z.string(),
  port: z.number().int(),
  token: z.string(),
  shortCode: z.string(),
  macName: z.string(),
  tailscaleHost: z.string().optional(),
});
export type QrPayload = z.infer<typeof ZQrPayload>;

/** Normalises a user-typed short code: strip spaces, uppercase, hyphens kept. */
export function normaliseShortCode(input: string): string {
  return input.replace(/\s+/g, "").toUpperCase();
}
