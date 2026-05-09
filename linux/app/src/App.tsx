import { JSX, onMount, onCleanup, createSignal, Show } from "solid-js";
import { useLocation, useNavigate } from "@solidjs/router";
import { listen } from "@tauri-apps/api/event";
import { Sidebar } from "./components/Sidebar";
import { useDaemonStream } from "./lib/daemon_ws";
import { applyTheme } from "./lib/theme";
import { isQuickAskRoute } from "./lib/routing";
import type { UnlistenFn } from "@tauri-apps/api/event";

interface Props {
  children?: JSX.Element;
}

export default function App(props: Props) {
  const location = useLocation();
  const navigate = useNavigate();
  const [updateAvailable, setUpdateAvailable] = createSignal(false);
  let unlistenUpdate: UnlistenFn | undefined;

  onMount(async () => {
    applyTheme();
    useDaemonStream();
    unlistenUpdate = await listen<{ available: boolean }>("updater:status", (event) => {
      setUpdateAvailable(event.payload.available);
    });
  });

  onCleanup(() => {
    unlistenUpdate?.();
  });

  const isQuickAsk = () => isQuickAskRoute(location.pathname);

  return (
    <Show
      when={!isQuickAsk()}
      fallback={<main class="h-full">{props.children}</main>}
    >
      <div class="grid grid-cols-[260px_1fr] h-full">
        <Sidebar
          onSettings={() => navigate("/settings")}
          onPairing={() => navigate("/pairing")}
          onVault={() => navigate("/vault")}
          updateAvailable={updateAvailable()}
          onUpdate={() => navigate("/updater")}
        />
        <main class="overflow-hidden">{props.children}</main>
      </div>
    </Show>
  );
}
