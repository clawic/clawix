import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { createSignal, onCleanup, onMount } from "solid-js";

export interface BridgeFrame {
  schemaVersion: number;
  body: { type: string; [k: string]: unknown };
}

const [chats, setChats] = createSignal<unknown[]>([]);
const [activeChatId, setActiveChatId] = createSignal<string | null>(null);
const [streamingMessages, setStreamingMessages] = createSignal<Record<string, unknown>>({});
const [bridgeState, setBridgeState] = createSignal<string>("booting");

export const daemonStore = {
  chats,
  activeChatId,
  setActiveChatId,
  streamingMessages,
  bridgeState,
  send: (body: BridgeFrame["body"]) => invoke("send_intent", { body })
};

export function useDaemonStream(): void {
  onMount(async () => {
    const unlisten = await listen<BridgeFrame[]>("bridge:frames", (event) => {
      for (const frame of event.payload) {
        switch (frame.body.type) {
          case "sessionsSnapshot":
            setChats((frame.body.sessions as unknown[]) ?? []);
            break;
          case "messagesSnapshot":
            setStreamingMessages((prev) => ({
              ...prev,
              [frame.body.sessionId as string]: frame.body.messages
            }));
            break;
          case "messageStreaming":
            setStreamingMessages((prev) => {
              const id = frame.body.sessionId as string;
              const list = (prev[id] as Array<Record<string, unknown>>) ?? [];
              const updated = list.map((m) =>
                m.id === frame.body.messageId
                  ? {
                      ...m,
                      content: frame.body.content,
                      reasoningText: frame.body.reasoningText,
                      streamingFinished: frame.body.finished
                    }
                  : m
              );
              return { ...prev, [id]: updated };
            });
            break;
          case "bridgeState":
            setBridgeState((frame.body.state as string) ?? "booting");
            break;
          default:
            break;
        }
      }
    });
    onCleanup(() => unlisten());
  });
}

export async function loadChats(): Promise<void> {
  const initial = await invoke<unknown[]>("get_chats");
  setChats(initial);
}

export async function sendMessage(text: string, chatId?: string): Promise<void> {
  await invoke("send_prompt", { args: { chatId, text } });
}
