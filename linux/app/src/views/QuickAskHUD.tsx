import { createSignal, onMount } from "solid-js";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";

export default function QuickAskHUD() {
  const [text, setText] = createSignal("");
  const [busy, setBusy] = createSignal(false);
  let inputRef: HTMLInputElement | undefined;

  onMount(() => {
    inputRef?.focus();
  });

  async function submit(e: SubmitEvent) {
    e.preventDefault();
    const value = text().trim();
    if (!value || busy()) return;
    setBusy(true);
    try {
      await invoke("send_prompt", { args: { chatId: null, text: value } });
      const win = getCurrentWindow();
      await win.hide();
      setText("");
    } finally {
      setBusy(false);
    }
  }

  async function injectSelectionFromActiveWindow() {
    try {
      const selection = await invoke<string>("read_primary_selection");
      if (selection) {
        setText((current) => `${current ? current + "\n" : ""}${selection}`);
      }
    } catch (_) {
      /* the user might not have a selection or wl-paste/xclip; quietly ignore */
    }
  }

  return (
    <section class="w-full h-full px-3 py-2 bg-white/80 dark:bg-zinc-900/80 backdrop-blur-glass">
      <form onSubmit={submit} class="flex items-center gap-2 h-full">
        <input
          ref={(el) => (inputRef = el)}
          type="text"
          class="flex-1 bg-transparent text-base focus:outline-none placeholder-zinc-400"
          placeholder="Ask Clawix anything…"
          value={text()}
          onInput={(e) => setText(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              void getCurrentWindow().hide();
            }
            if (e.key === "Tab") {
              e.preventDefault();
              void injectSelectionFromActiveWindow();
            }
          }}
        />
        <button
          type="submit"
          class="px-3 py-1.5 rounded-lg bg-zinc-900 text-white text-xs font-medium dark:bg-zinc-100 dark:text-zinc-900 disabled:opacity-40"
          disabled={!text().trim() || busy()}
        >
          Send
        </button>
      </form>
    </section>
  );
}
