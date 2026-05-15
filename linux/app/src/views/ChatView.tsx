import { For, Show, createMemo, createSignal, onMount } from "solid-js";
import { useParams } from "@solidjs/router";
import { createVirtualizer } from "@tanstack/solid-virtual";
import { daemonStore, loadChats, sendMessage } from "../lib/daemon_ws";
import { renderMarkdown } from "../lib/markdown";

interface Message {
  id: string;
  role: "user" | "assistant" | "system";
  content: string;
  reasoningText?: string;
  streamingFinished?: boolean;
}

export default function ChatView() {
  const params = useParams<{ id?: string }>();
  const [composer, setComposer] = createSignal("");
  const [scrollEl, setScrollEl] = createSignal<HTMLDivElement | undefined>();

  onMount(() => {
    void loadChats();
  });

  const messages = createMemo<Message[]>(() => {
    const id = params.id ?? daemonStore.activeChatId() ?? "";
    if (!id) return [];
    return ((daemonStore.streamingMessages()[id] as Message[]) ?? []).filter(
      (m) => m && (m.role === "user" || m.role === "assistant")
    );
  });

  const virtualizer = createMemo(() =>
    createVirtualizer({
      count: messages().length,
      getScrollElement: () => scrollEl() ?? null,
      estimateSize: () => 96,
      overscan: 8
    })
  );

  async function onSubmit(e: SubmitEvent) {
    e.preventDefault();
    const text = composer().trim();
    if (!text) return;
    setComposer("");
    await sendMessage(text, params.id);
  }

  return (
    <section class="flex flex-col h-full">
      <header class="px-6 py-3 border-b border-zinc-200/60 dark:border-zinc-800/60 flex items-center gap-3">
        <h1 class="text-sm font-medium tracking-tightish">
          {params.id ? "Conversation" : "New chat"}
        </h1>
        <span class="text-xs text-zinc-500">{daemonStore.bridgeState()}</span>
      </header>

      <div ref={(el) => setScrollEl(el)} class="flex-1 overflow-auto px-6 py-4">
        <Show when={messages().length === 0}>
          <div class="h-full flex items-center justify-center text-zinc-400 text-sm">
            Start a conversation.
          </div>
        </Show>
        <div
          style={{
            height: `${virtualizer().getTotalSize()}px`,
            position: "relative",
            width: "100%"
          }}
        >
          <For each={virtualizer().getVirtualItems()}>
            {(virtualRow) => {
              const msg = messages()[virtualRow.index];
              return (
                <article
                  data-role={msg.role}
                  ref={(el) => virtualizer().measureElement(el)}
                  data-index={virtualRow.index}
                  class="absolute left-0 right-0"
                  style={{ transform: `translateY(${virtualRow.start}px)` }}
                >
                  <div
                    class="max-w-2xl mx-auto py-3"
                    classList={{
                      "text-zinc-900 dark:text-zinc-100": true
                    }}
                  >
                    <Show when={msg.role === "user"}>
                      <div class="text-xs uppercase tracking-tighter2 text-zinc-500 mb-1">
                        You
                      </div>
                    </Show>
                    <div
                      class="prose prose-sm dark:prose-invert max-w-none leading-relaxed"
                      innerHTML={renderMarkdown(msg.content)}
                    />
                    <Show when={msg.streamingFinished === false}>
                      <div class="mt-1 inline-block w-1.5 h-4 bg-zinc-400 dark:bg-zinc-500 animate-pulse" />
                    </Show>
                  </div>
                </article>
              );
            }}
          </For>
        </div>
      </div>

      <form
        onSubmit={onSubmit}
        class="border-t border-zinc-200/60 dark:border-zinc-800/60 px-6 py-3"
      >
        <div class="max-w-2xl mx-auto flex items-end gap-2">
          <textarea
            class="flex-1 resize-none rounded-xl bg-zinc-100/70 dark:bg-zinc-800/40 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-zinc-300 dark:focus:ring-zinc-700 min-h-[44px] max-h-[160px]"
            placeholder="Message Clawix"
            value={composer()}
            onInput={(e) => setComposer(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                e.currentTarget.form?.requestSubmit();
              }
            }}
          />
          <button
            type="submit"
            class="px-4 py-2 rounded-xl bg-zinc-900 text-white text-sm font-medium dark:bg-zinc-100 dark:text-zinc-900 disabled:opacity-40"
            disabled={!composer().trim()}
          >
            Send
          </button>
        </div>
      </form>
    </section>
  );
}
