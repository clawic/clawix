import { For, Show, createMemo } from "solid-js";
import { A } from "@solidjs/router";
import { daemonStore } from "../lib/daemon_ws";

interface ChatBrief {
  id: string;
  title: string;
  hasActiveTurn?: boolean;
}

interface Props {
  onSettings: () => void;
  onPairing: () => void;
  onVault: () => void;
  updateAvailable: boolean;
  onUpdate: () => void;
}

export function Sidebar(props: Props) {
  const chats = createMemo(() => (daemonStore.chats() as ChatBrief[]) ?? []);

  return (
    <aside class="h-full bg-white/60 dark:bg-zinc-900/60 backdrop-blur-glass border-r border-zinc-200/60 dark:border-zinc-800/60 flex flex-col">
      <header class="px-4 pt-5 pb-3 flex items-center justify-between">
        <div class="text-sm font-semibold tracking-tightish">Clawix</div>
        <Show when={props.updateAvailable}>
          <button
            class="text-[11px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
            onClick={props.onUpdate}
          >
            Update
          </button>
        </Show>
      </header>

      <nav class="px-2 pb-2 space-y-0.5">
        <A
          href="/"
          end
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          New chat
        </A>
      </nav>

      <div class="flex-1 overflow-y-auto px-2 space-y-0.5">
        <For each={chats()}>
          {(chat) => (
            <A
              href={`/chats/${chat.id}`}
              class="block px-3 py-2 text-sm rounded-lg row-hover truncate"
              activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
            >
              {chat.title || "Untitled"}
            </A>
          )}
        </For>
      </div>

      <footer class="px-2 pb-3 pt-2 border-t border-zinc-200/60 dark:border-zinc-800/60 space-y-0.5">
        <button
          class="w-full text-left px-3 py-2 text-sm rounded-lg row-hover"
          onClick={props.onPairing}
        >
          Pair iPhone
        </button>
        <button
          class="w-full text-left px-3 py-2 text-sm rounded-lg row-hover"
          onClick={props.onVault}
        >
          Vault
        </button>
        <button
          class="w-full text-left px-3 py-2 text-sm rounded-lg row-hover"
          onClick={props.onSettings}
        >
          Settings
        </button>
      </footer>
    </aside>
  );
}
