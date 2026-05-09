import { Show, createSignal, onMount } from "solid-js";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";

export default function UpdaterDialog() {
  const [update, setUpdate] = createSignal<Update | null>(null);
  const [progress, setProgress] = createSignal<number | null>(null);
  const [status, setStatus] = createSignal<"idle" | "checking" | "downloading" | "ready" | "error">(
    "idle"
  );
  const [error, setError] = createSignal<string | null>(null);

  onMount(async () => {
    setStatus("checking");
    try {
      const u = await check();
      if (u) setUpdate(u);
      setStatus("idle");
    } catch (err) {
      setError(String(err));
      setStatus("error");
    }
  });

  async function install() {
    const u = update();
    if (!u) return;
    setStatus("downloading");
    let downloaded = 0;
    let total = 0;
    try {
      await u.downloadAndInstall((event) => {
        switch (event.event) {
          case "Started":
            total = event.data.contentLength ?? 0;
            break;
          case "Progress":
            downloaded += event.data.chunkLength;
            if (total > 0) setProgress(Math.round((downloaded / total) * 100));
            break;
          case "Finished":
            setStatus("ready");
            break;
        }
      });
      await relaunch();
    } catch (err) {
      setError(String(err));
      setStatus("error");
    }
  }

  return (
    <section class="h-full flex items-center justify-center px-8">
      <div class="max-w-md w-full text-center space-y-4">
        <h1 class="text-xl font-semibold tracking-tightish">Software update</h1>
        <Show when={status() === "checking"}>
          <p class="text-sm text-zinc-500">Checking for updates…</p>
        </Show>
        <Show when={status() === "idle" && !update()}>
          <p class="text-sm text-zinc-500">You're up to date.</p>
        </Show>
        <Show when={update()}>
          <div class="space-y-3 text-left">
            <div class="text-sm">
              Version <span class="font-medium">{update()?.version}</span> is available.
            </div>
            <Show when={update()?.body}>
              <pre class="text-xs whitespace-pre-wrap bg-zinc-100/70 dark:bg-zinc-800/40 p-3 rounded-lg max-h-64 overflow-auto">
                {update()?.body}
              </pre>
            </Show>
            <Show when={status() !== "downloading"}>
              <button
                class="w-full px-4 py-2 rounded-lg bg-zinc-900 text-white text-sm font-medium dark:bg-zinc-100 dark:text-zinc-900"
                onClick={install}
              >
                Download and install
              </button>
            </Show>
            <Show when={status() === "downloading"}>
              <div class="w-full bg-zinc-200/70 dark:bg-zinc-800/40 rounded-full h-1.5 overflow-hidden">
                <div
                  class="h-full bg-emerald-500 transition-all duration-200"
                  style={{ width: `${progress() ?? 0}%` }}
                />
              </div>
              <div class="text-xs text-zinc-500 text-center">{progress() ?? 0}%</div>
            </Show>
          </div>
        </Show>
        <Show when={error()}>
          <p class="text-sm text-red-500">{error()}</p>
        </Show>
      </div>
    </section>
  );
}
