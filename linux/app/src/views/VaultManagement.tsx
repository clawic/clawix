import { Show, createSignal } from "solid-js";

export default function VaultManagement() {
  const [step, setStep] = createSignal<"locked" | "unlocked" | "create">("locked");
  const [pass, setPass] = createSignal("");

  return (
    <section class="h-full overflow-auto">
      <div class="max-w-md mx-auto px-8 py-10 space-y-6">
        <header>
          <h1 class="text-xl font-semibold tracking-tightish">Vault</h1>
          <p class="text-sm text-zinc-500 mt-1">
            Local secrets. Encrypted with Argon2id and ChaCha20-Poly1305 on disk.
          </p>
        </header>

        <Show when={step() === "locked"}>
          <form
            class="space-y-3"
            onSubmit={(e) => {
              e.preventDefault();
              setStep("unlocked");
            }}
          >
            <input
              type="password"
              class="w-full px-3 py-2 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
              placeholder="Vault passphrase"
              value={pass()}
              onInput={(e) => setPass(e.currentTarget.value)}
            />
            <button
              type="submit"
              class="w-full px-4 py-2 rounded-lg bg-zinc-900 text-white text-sm font-medium dark:bg-zinc-100 dark:text-zinc-900"
              disabled={!pass()}
            >
              Unlock
            </button>
            <button
              type="button"
              class="w-full px-4 py-2 rounded-lg text-sm text-zinc-500"
              onClick={() => setStep("create")}
            >
              Create a new vault…
            </button>
          </form>
        </Show>

        <Show when={step() === "create"}>
          <div class="space-y-3">
            <p class="text-sm text-zinc-500">
              Pick a strong passphrase. We'll derive a master key with Argon2id and show you a 24-word
              recovery phrase you can use to restore access.
            </p>
            <input
              type="password"
              class="w-full px-3 py-2 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
              placeholder="New passphrase"
            />
            <input
              type="password"
              class="w-full px-3 py-2 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm"
              placeholder="Confirm passphrase"
            />
            <button
              type="button"
              class="w-full px-4 py-2 rounded-lg bg-zinc-900 text-white text-sm font-medium dark:bg-zinc-100 dark:text-zinc-900"
              onClick={() => setStep("unlocked")}
            >
              Create vault
            </button>
          </div>
        </Show>

        <Show when={step() === "unlocked"}>
          <div class="space-y-3">
            <div class="text-sm">No secrets yet.</div>
            <button class="px-3 py-1.5 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-sm">
              Add secret
            </button>
          </div>
        </Show>
      </div>
    </section>
  );
}
