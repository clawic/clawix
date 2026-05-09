/**
 * Main shell. Holds the nav rail, the (route-specific) sidebar, and the
 * current route view. Connection / version / status indicators live in
 * the top chrome.
 */
import { useEffect, useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import { storage, StorageKeys } from "../../lib/storage";
import { NavRail, type NavRoute } from "./nav-rail";
import { SidebarView } from "../sidebar/sidebar-view";
import { ChatView } from "../chat/chat-view";
import { SettingsView } from "../settings/settings-view";
import { MemoryView } from "../memory/memory-view";
import { SecretsView } from "../secrets/secrets-view";
import { ProjectsView } from "../projects/projects-view";
import { DatabaseView } from "../database/database-view";
import { McpView } from "../mcp/mcp-view";
import { LocalModelsView } from "../local-models/local-models-view";
import { StatusIndicator } from "../../components/status-indicator";
import { VersionMismatchBanner } from "./version-mismatch";

export function MainShell() {
  const [route, setRoute] = useState<NavRoute>("chat");
  const [chatId, setChatId] = useState<string | null>(() => storage.get<string>(StorageKeys.lastChatId));
  const newChat = useBridgeStore((s) => s.newChat);
  const conn = useBridgeStore((s) => s.connection);
  const macName = useBridgeStore((s) => s.macName);

  useEffect(() => {
    if (chatId) storage.set(StorageKeys.lastChatId, chatId);
  }, [chatId]);

  return (
    <div className="h-full flex">
      <NavRail current={route} onChange={setRoute} />
      <div className="flex-1 min-w-0 flex flex-col">
        <div className="h-[36px] px-4 flex items-center justify-between border-b border-[var(--color-border)] bg-[var(--color-bg)]/85 backdrop-blur">
          <div className="text-[12px] text-[var(--color-fg-muted)]">
            {macName ? `Bridged to ${macName}` : "Clawix"}
          </div>
          <StatusIndicator />
        </div>

        {conn.kind === "version-mismatch" && <VersionMismatchBanner serverVersion={conn.serverVersion} />}

        <div className="flex-1 min-h-0">
          {route === "chat" && (
            <div className="h-full flex">
              <SidebarView
                selectedChatId={chatId}
                onSelect={(id) => setChatId(id)}
                onNew={() => {
                  const id = newChat("");
                  setChatId(id);
                }}
              />
              <div className="flex-1 min-w-0">
                <ChatView chatId={chatId} />
              </div>
            </div>
          )}
          {route === "projects" && <ProjectsView />}
          {route === "memory" && <MemoryView />}
          {route === "secrets" && <SecretsView />}
          {route === "database" && <DatabaseView />}
          {route === "mcp" && <McpView />}
          {route === "local-models" && <LocalModelsView />}
          {route === "settings" && <SettingsView />}
        </div>
      </div>
    </div>
  );
}
