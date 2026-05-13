import { For, Show, createSignal, onMount } from "solid-js";
import { invoke } from "@tauri-apps/api/core";

interface DaemonStatus {
  installed: boolean;
  running: boolean;
  version: string | null;
}

export default function SettingsView() {
  const [status, setStatus] = createSignal<DaemonStatus | null>(null);
  const [advancedOpen, setAdvancedOpen] = createSignal(false);
  const [hotkey, setHotkey] = createSignal("Super+Space");
  const [theme, setTheme] = createSignal<"system" | "light" | "dark">("system");

  onMount(async () => {
    const s = await invoke<DaemonStatus>("daemon_status");
    setStatus(s);
    const stored = await invoke<string | null>("get_setting", { key: "ui.hotkey" });
    if (stored) setHotkey(stored);
    const t = await invoke<string | null>("get_setting", { key: "ui.theme" });
    if (t === "light" || t === "dark" || t === "system") setTheme(t);
  });

  async function persist(key: string, value: string) {
    await invoke("set_setting", { key, value });
  }

  return (
    <section class="h-full overflow-auto">
      <div class="max-w-2xl mx-auto px-8 py-8 space-y-8">
        <header>
          <h1 class="text-2xl font-semibold tracking-tightish">Settings</h1>
          <p class="text-sm text-zinc-500 mt-1">Tune how Clawix behaves on this machine.</p>
        </header>

        <Section title="General">
          <Field label="QuickAsk hotkey" hint="Captured via the desktop portal on Wayland.">
            <input
              type="text"
              class="w-48 px-3 py-1.5 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
              value={hotkey()}
              onChange={(e) => {
                setHotkey(e.currentTarget.value);
                void persist("ui.hotkey", e.currentTarget.value);
              }}
            />
          </Field>
          <Field label="Theme">
            <select
              class="px-3 py-1.5 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
              value={theme()}
              onChange={(e) => {
                const v = e.currentTarget.value as "system" | "light" | "dark";
                setTheme(v);
                void persist("ui.theme", v);
              }}
            >
              <option value="system">Match system</option>
              <option value="light">Always light</option>
              <option value="dark">Always dark</option>
            </select>
          </Field>
        </Section>

        <Section title="Bridge daemon">
          <Show when={status()}>
            <div class="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
              <div>Status: {status()?.running ? "running" : "stopped"}</div>
              <div>Installed: {status()?.installed ? "yes" : "no"}</div>
              <div>Version: {status()?.version ?? "unknown"}</div>
            </div>
          </Show>
        </Section>

        <details
          class="border-t border-zinc-200/60 dark:border-zinc-800/60 pt-4"
          open={advancedOpen()}
          onToggle={(e) => setAdvancedOpen(e.currentTarget.open)}
        >
          <summary class="text-sm text-zinc-500 cursor-pointer select-none">Advanced</summary>
          <div class="mt-4 space-y-4">
            <Section title="Diagnostics">
              <Field label="Bridge port">
                <input
                  type="number"
                  class="w-32 px-3 py-1.5 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
                  value={24080}
                  onChange={(e) => persist("daemon.port", e.currentTarget.value)}
                />
              </Field>
              <Field label="Log level">
                <select
                  class="px-3 py-1.5 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
                  onChange={(e) => persist("daemon.logLevel", e.currentTarget.value)}
                >
                  <For each={["info", "debug", "warn", "error"]}>
                    {(level) => <option value={level}>{level}</option>}
                  </For>
                </select>
              </Field>
            </Section>
          </div>
        </details>
      </div>
    </section>
  );
}

function Section(props: { title: string; children: any }) {
  return (
    <section class="space-y-3">
      <h2 class="text-sm font-medium text-zinc-700 dark:text-zinc-200">{props.title}</h2>
      <div class="space-y-3">{props.children}</div>
    </section>
  );
}

function Field(props: { label: string; hint?: string; children: any }) {
  return (
    <div class="flex items-center justify-between gap-4">
      <div>
        <div class="text-sm">{props.label}</div>
        <Show when={props.hint}>
          <div class="text-xs text-zinc-500 mt-0.5">{props.hint}</div>
        </Show>
      </div>
      <div>{props.children}</div>
    </div>
  );
}
