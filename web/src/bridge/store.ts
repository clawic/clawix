/**
 * Zustand store mirroring `BridgeStore` from iOS at
 * `clawix/ios/Sources/Clawix/Bridge/BridgeStore.swift`. Listens to the
 * BridgeClient and re-derives the UI state from incoming frames.
 *
 * Design contract: chats, messages and projects come from the daemon on
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
  chats: WireChat[];
  projects: WireProject[];
  /** Indexed by chatId. Only populated for chats the user has opened. */
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

  openChat(chatId: string, useInitialPage?: boolean): void;
  loadOlderMessages(chatId: string): void;
  sendPrompt(chatId: string, text: string, attachments?: WireMessage["attachments"]): void;
  newChat(text: string, attachments?: WireMessage["attachments"]): string;
  interruptTurn(chatId: string): void;
  editPrompt(chatId: string, messageId: string, text: string): void;
  archive(chatId: string): void;
  unarchive(chatId: string): void;
  pin(chatId: string): void;
  unpin(chatId: string): void;
  rename(chatId: string, title: string): void;
  listProjects(): void;
  readFile(path: string): void;
  requestAudio(audioId: string): void;
  requestGeneratedImage(path: string): void;
  requestRateLimits(): void;
  transcribeAudio(audioBase64: string, mimeType: string, language?: string): string;
}

export const useBridgeStore = create<BridgeStoreState>()(
  subscribeWithSelector((set, get) => ({
    client: null,
    connection: { kind: "idle" } satisfies ConnectionState,
    bridge: { state: "booting", chatCount: 0 },
    macName: null,
    chats: [],
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
        projects: [],
        messagesByChat: {},
        hasMoreByChat: {},
        macName: null,
        rateLimits: null,
        rateLimitsByLimitId: {},
      });
    },

    openChat(chatId, useInitialPage = true) {
      const client = get().client;
      if (!client) return;
      client.send({
        type: "openChat",
        chatId,
        ...(useInitialPage ? { limit: BRIDGE_INITIAL_PAGE_LIMIT } : {}),
      });
    },

    loadOlderMessages(chatId) {
      const client = get().client;
      const msgs = get().messagesByChat[chatId];
      if (!client || !msgs || msgs.length === 0) return;
      const beforeMessageId = msgs[0]!.id;
      client.send({
        type: "loadOlderMessages",
        chatId,
        beforeMessageId,
        limit: BRIDGE_OLDER_PAGE_LIMIT,
      });
    },

    sendPrompt(chatId, text, attachments = []) {
      const client = get().client;
      if (!client) return;
      client.send({ type: "sendPrompt", chatId, text, attachments });
    },

    newChat(text, attachments = []) {
      const client = get().client;
      const chatId = uuidv4();
      if (!client) return chatId;
      client.send({ type: "newChat", chatId, text, attachments });
      return chatId;
    },

    interruptTurn(chatId) {
      get().client?.send({ type: "interruptTurn", chatId });
    },

    editPrompt(chatId, messageId, text) {
      get().client?.send({ type: "editPrompt", chatId, messageId, text });
    },

    archive(chatId) { get().client?.send({ type: "archiveChat", chatId }); },
    unarchive(chatId) { get().client?.send({ type: "unarchiveChat", chatId }); },
    pin(chatId) { get().client?.send({ type: "pinChat", chatId }); },
    unpin(chatId) { get().client?.send({ type: "unpinChat", chatId }); },
    rename(chatId, title) { get().client?.send({ type: "renameChat", chatId, title }); },

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
    case "chatsSnapshot":
      set({ chats: sortChats(frame.chats) });
      break;
    case "chatUpdated": {
      const { chats } = get();
      const idx = chats.findIndex((c) => c.id === frame.chat.id);
      const next = idx >= 0 ? chats.with(idx, frame.chat) : [...chats, frame.chat];
      set({ chats: sortChats(next) });
      break;
    }
    case "messagesSnapshot": {
      const messagesByChat = { ...get().messagesByChat, [frame.chatId]: frame.messages };
      const hasMoreByChat = { ...get().hasMoreByChat, [frame.chatId]: frame.hasMore ?? false };
      set({ messagesByChat, hasMoreByChat });
      break;
    }
    case "messagesPage": {
      const cur = get().messagesByChat[frame.chatId] ?? [];
      const merged = [...frame.messages, ...cur];
      const messagesByChat = { ...get().messagesByChat, [frame.chatId]: dedupeById(merged) };
      const hasMoreByChat = { ...get().hasMoreByChat, [frame.chatId]: frame.hasMore };
      set({ messagesByChat, hasMoreByChat });
      break;
    }
    case "messageAppended": {
      const cur = get().messagesByChat[frame.chatId] ?? [];
      const messagesByChat = {
        ...get().messagesByChat,
        [frame.chatId]: dedupeById([...cur, frame.message]),
      };
      set({ messagesByChat });
      break;
    }
    case "messageStreaming": {
      const cur = get().messagesByChat[frame.chatId] ?? [];
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
      set({ messagesByChat: { ...get().messagesByChat, [frame.chatId]: next } });
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

function sortChats(chats: WireChat[]): WireChat[] {
  return [...chats].sort((a, b) => {
    if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
    const aTs = a.lastMessageAt ? Date.parse(a.lastMessageAt) : Date.parse(a.createdAt);
    const bTs = b.lastMessageAt ? Date.parse(b.lastMessageAt) : Date.parse(b.createdAt);
    return bTs - aTs;
  });
}

function dedupeById<T extends { id: string }>(items: T[]): T[] {
  const seen = new Map<string, T>();
  for (const item of items) seen.set(item.id, item);
  return [...seen.values()];
}
