/**
 * Zustand store mirroring `BridgeStore` from iOS at
 * `clawix/ios/Sources/Clawix/Bridge/BridgeStore.swift`. Listens to the
 * BridgeClient and re-derives the UI state from incoming frames.
 *
 * Design contract: sessions, messages and projects come from the daemon on
 * every connection. We do NOT persist them locally. The only thing the
 * web SPA persists is the pairing token (so a refresh doesn't re-pair).
 */

import { create } from "zustand";
import { subscribeWithSelector } from "zustand/middleware";
import { BridgeClient, type ConnectionState } from "./client";
import {
  BRIDGE_INITIAL_PAGE_LIMIT,
  BRIDGE_OLDER_PAGE_LIMIT,
  type BridgeFrame,
} from "./frames";
import type {
  WireAudioAttachTranscriptInput,
  WireAudioListFilter,
  WireAudioRegisterRequest,
  WireChat,
  WireMessage,
  WireProject,
  WireRateLimitSnapshot,
} from "./wire";
import { storage, StorageKeys } from "../lib/storage";
import { uuidv4 } from "../lib/uuid";

export interface BridgeRuntime {
  /** "booting" | "syncing" | "ready" | "error" */
  state: string;
  chatCount: number;
  message?: string;
}

export interface BridgeStoreState {
  client: BridgeClient | null;
  connection: ConnectionState;
  bridge: BridgeRuntime;
  macName: string | null;
  /** UI vocabulary. Wire frames call these sessions. */
  chats: WireChat[];
  sessions: WireChat[];
  projects: WireProject[];
  /** Indexed by sessionId. Only populated for sessions the user has opened. */
  messagesByChat: Record<string, WireMessage[]>;
  /** True when more older messages can be fetched. */
  hasMoreByChat: Record<string, boolean>;
  rateLimits: WireRateLimitSnapshot | null;
  rateLimitsByLimitId: Record<string, WireRateLimitSnapshot>;
  files: Record<string, { content?: string; isMarkdown: boolean; error?: string }>;
  audioById: Record<string, { mimeType: string; base64: string } | { error: string }>;
  imagesByPath: Record<string, { mimeType: string; base64: string } | { error: string }>;

  /** Mutators */
  attach(token: string): void;
  detach(): void;

  openSession(sessionId: string, useInitialPage?: boolean): void;
  openChat(chatId: string, useInitialPage?: boolean): void;
  loadOlderMessages(sessionId: string): void;
  sendPrompt(sessionId: string, text: string, attachments?: WireMessage["attachments"]): void;
  newSession(text: string, attachments?: WireMessage["attachments"]): string;
  newChat(text: string, attachments?: WireMessage["attachments"]): string;
  interruptTurn(sessionId: string): void;
  editPrompt(sessionId: string, messageId: string, text: string): void;
  archive(sessionId: string): void;
  unarchive(sessionId: string): void;
  pin(sessionId: string): void;
  unpin(sessionId: string): void;
  rename(sessionId: string, title: string): void;
  listProjects(): void;
  readFile(path: string): void;
  requestAudio(audioId: string): void;
  requestGeneratedImage(path: string): void;
  requestRateLimits(): void;
  transcribeAudio(audioBase64: string, mimeType: string, language?: string): string;

  /** v7 audio catalog. Each method returns the `requestId` consumers should
   *  use with `client.onFrame("audioXxxResult")` to await the response.
   */
  audioRegister(request: WireAudioRegisterRequest): string;
  audioAttachTranscript(audioId: string, input: WireAudioAttachTranscriptInput): string;
  audioGet(audioId: string, appId: string): string;
  audioGetBytes(audioId: string, appId: string): string;
  audioList(filter: WireAudioListFilter): string;
  audioDelete(audioId: string, appId: string): string;
}

export const useBridgeStore = create<BridgeStoreState>()(
  subscribeWithSelector((set, get) => ({
    client: null,
    connection: { kind: "idle" } satisfies ConnectionState,
    bridge: { state: "booting", chatCount: 0 },
    macName: null,
    chats: [],
    sessions: [],
    projects: [],
    messagesByChat: {},
    hasMoreByChat: {},
    rateLimits: null,
    rateLimitsByLimitId: {},
    files: {},
    audioById: {},
    imagesByPath: {},

    attach(token: string) {
      const existing = get().client;
      if (existing) existing.stop();

      const client = new BridgeClient({
        token,
        deviceName: storage.get<string>(StorageKeys.deviceName) ?? undefined,
      });
      client.onState((state) => set({ connection: state }));
      client.on((frame) => applyFrame(set, get, frame));
      client.start();
      set({ client });
    },

    detach() {
      const client = get().client;
      if (client) client.stop();
      set({
        client: null,
        connection: { kind: "idle" },
        chats: [],
        sessions: [],
        projects: [],
        messagesByChat: {},
        hasMoreByChat: {},
        macName: null,
        rateLimits: null,
        rateLimitsByLimitId: {},
      });
    },

    openSession(sessionId, useInitialPage = true) {
      const client = get().client;
      if (!client) return;
      client.send({
        type: "openSession",
        sessionId,
        ...(useInitialPage ? { limit: BRIDGE_INITIAL_PAGE_LIMIT } : {}),
      });
    },
    openChat(chatId, useInitialPage = true) {
      get().openSession(chatId, useInitialPage);
    },

    loadOlderMessages(sessionId) {
      const client = get().client;
      const msgs = get().messagesByChat[sessionId];
      if (!client || !msgs || msgs.length === 0) return;
      const beforeMessageId = msgs[0]!.id;
      client.send({
        type: "loadOlderMessages",
        sessionId,
        beforeMessageId,
        limit: BRIDGE_OLDER_PAGE_LIMIT,
      });
    },

    sendPrompt(sessionId, text, attachments = []) {
      const client = get().client;
      if (!client) return;
      client.send({ type: "sendPrompt", sessionId, text, attachments });
    },

    newSession(text, attachments = []) {
      const client = get().client;
      const sessionId = uuidv4();
      if (!client) return sessionId;
      client.send({ type: "newSession", sessionId, text, attachments });
      return sessionId;
    },
    newChat(text, attachments = []) {
      return get().newSession(text, attachments);
    },

    interruptTurn(sessionId) {
      get().client?.send({ type: "interruptTurn", sessionId });
    },

    editPrompt(sessionId, messageId, text) {
      get().client?.send({ type: "editPrompt", sessionId, messageId, text });
    },

    archive(sessionId) { get().client?.send({ type: "archiveSession", sessionId }); },
    unarchive(sessionId) { get().client?.send({ type: "unarchiveSession", sessionId }); },
    pin(sessionId) { get().client?.send({ type: "pinSession", sessionId }); },
    unpin(sessionId) { get().client?.send({ type: "unpinSession", sessionId }); },
    rename(sessionId, title) { get().client?.send({ type: "renameSession", sessionId, title }); },

    listProjects() { get().client?.send({ type: "listProjects" }); },
    readFile(path) { get().client?.send({ type: "readFile", path }); },
    requestAudio(audioId) { get().client?.send({ type: "requestAudio", audioId }); },
    requestGeneratedImage(path) { get().client?.send({ type: "requestGeneratedImage", path }); },
    requestRateLimits() { get().client?.send({ type: "requestRateLimits" }); },

    transcribeAudio(audioBase64, mimeType, language) {
      const requestId = uuidv4();
      get().client?.send({
        type: "transcribeAudio",
        requestId,
        audioBase64,
        mimeType,
        ...(language ? { language } : {}),
      });
      return requestId;
    },

    audioRegister(request) {
      const requestId = uuidv4();
      get().client?.send({ type: "audioRegister", requestId, request });
      return requestId;
    },
    audioAttachTranscript(audioId, input) {
      const requestId = uuidv4();
      get().client?.send({ type: "audioAttachTranscript", requestId, audioId, transcript: input });
      return requestId;
    },
    audioGet(audioId, appId) {
      const requestId = uuidv4();
      get().client?.send({ type: "audioGet", requestId, audioId, appId });
      return requestId;
    },
    audioGetBytes(audioId, appId) {
      const requestId = uuidv4();
      get().client?.send({ type: "audioGetBytes", requestId, audioId, appId });
      return requestId;
    },
    audioList(filter) {
      const requestId = uuidv4();
      get().client?.send({ type: "audioList", requestId, filter });
      return requestId;
    },
    audioDelete(audioId, appId) {
      const requestId = uuidv4();
      get().client?.send({ type: "audioDelete", requestId, audioId, appId });
      return requestId;
    },
  })),
);

type Set = (
  partial: Partial<BridgeStoreState> | ((state: BridgeStoreState) => Partial<BridgeStoreState>),
) => void;

type Get = () => BridgeStoreState;

function applyFrame(set: Set, get: Get, frame: BridgeFrame): void {
  switch (frame.type) {
    case "authOk":
      set({ macName: frame.macName ?? null });
      get().requestRateLimits();
      get().listProjects();
      break;
    case "sessionsSnapshot":
      setSessions(set, sortSessions(frame.sessions));
      break;
    case "chatUpdated": {
      const { sessions } = get();
      const idx = sessions.findIndex((c) => c.id === frame.chat.id);
      const next = idx >= 0 ? sessions.with(idx, frame.chat) : [...sessions, frame.chat];
      setSessions(set, sortSessions(next));
      break;
    }
    case "messagesSnapshot": {
      const messagesByChat = { ...get().messagesByChat, [frame.sessionId]: frame.messages };
      const hasMoreByChat = { ...get().hasMoreByChat, [frame.sessionId]: frame.hasMore ?? false };
      set({ messagesByChat, hasMoreByChat });
      break;
    }
    case "messagesPage": {
      const cur = get().messagesByChat[frame.sessionId] ?? [];
      const merged = [...frame.messages, ...cur];
      const messagesByChat = { ...get().messagesByChat, [frame.sessionId]: dedupeById(merged) };
      const hasMoreByChat = { ...get().hasMoreByChat, [frame.sessionId]: frame.hasMore };
      set({ messagesByChat, hasMoreByChat });
      break;
    }
    case "messageAppended": {
      const cur = get().messagesByChat[frame.sessionId] ?? [];
      const messagesByChat = {
        ...get().messagesByChat,
        [frame.sessionId]: dedupeById([...cur, frame.message]),
      };
      set({ messagesByChat });
      break;
    }
    case "messageStreaming": {
      const cur = get().messagesByChat[frame.sessionId] ?? [];
      const idx = cur.findIndex((m) => m.id === frame.messageId);
      let next: WireMessage[];
      if (idx >= 0) {
        const updated: WireMessage = {
          ...cur[idx]!,
          content: frame.content,
          reasoningText: frame.reasoningText,
          streamingFinished: frame.finished,
        };
        next = cur.with(idx, updated);
      } else {
        next = [
          ...cur,
          {
            id: frame.messageId,
            role: "assistant",
            content: frame.content,
            reasoningText: frame.reasoningText,
            streamingFinished: frame.finished,
            isError: false,
            timestamp: new Date().toISOString(),
            timeline: [],
            attachments: [],
          } satisfies WireMessage,
        ];
      }
      set({ messagesByChat: { ...get().messagesByChat, [frame.sessionId]: next } });
      break;
    }
    case "errorEvent":
      console.error("[bridge errorEvent]", frame.code, frame.message);
      break;
    case "projectsSnapshot":
      set({ projects: frame.projects });
      break;
    case "fileSnapshot":
      set({
        files: {
          ...get().files,
          [frame.path]: {
            content: frame.content,
            isMarkdown: frame.isMarkdown,
            error: frame.error,
          },
        },
      });
      break;
    case "audioSnapshot":
      set({
        audioById: {
          ...get().audioById,
          [frame.audioId]: frame.audioBase64
            ? { mimeType: frame.mimeType ?? "audio/mp4", base64: frame.audioBase64 }
            : { error: frame.errorMessage ?? "Audio no longer available" },
        },
      });
      break;
    case "generatedImageSnapshot":
      set({
        imagesByPath: {
          ...get().imagesByPath,
          [frame.path]: frame.dataBase64
            ? { mimeType: frame.mimeType ?? "image/png", base64: frame.dataBase64 }
            : { error: frame.errorMessage ?? "Image not available" },
        },
      });
      break;
    case "bridgeState":
      set({ bridge: { state: frame.state, chatCount: frame.chatCount, message: frame.message } });
      break;
    case "rateLimitsSnapshot":
    case "rateLimitsUpdated":
      set({
        rateLimits: frame.rateLimits ?? null,
        rateLimitsByLimitId: frame.rateLimitsByLimitId ?? {},
      });
      break;
    case "transcriptionResult":
      // Consumers (e.g. Composer) subscribe to client.onFrame("transcriptionResult").
      break;
    case "pairingPayload":
      // Consumed by PairingScreen via direct frame subscription.
      break;
    default:
      break;
  }
}

function sortSessions(sessions: WireChat[]): WireChat[] {
  return [...sessions].sort((a, b) => {
    if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
    const aTs = a.lastMessageAt ? Date.parse(a.lastMessageAt) : Date.parse(a.createdAt);
    const bTs = b.lastMessageAt ? Date.parse(b.lastMessageAt) : Date.parse(b.createdAt);
    return bTs - aTs;
  });
}

function setSessions(set: Set, sessions: WireChat[]): void {
  set({ sessions, chats: sessions });
}

function dedupeById<T extends { id: string }>(items: T[]): T[] {
  const seen = new Map<string, T>();
  for (const item of items) seen.set(item.id, item);
  return [...seen.values()];
}
