// Main shell. Mirrors the Mac ContentView (left sidebar resizable +
// content area with continuous-corner squircle + optional right sidebar).
// The "nav rail" of the previous version is gone: routes live as a row at
// the top of the sidebar, exactly like the Mac.
import { useEffect, useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import { storage, StorageKeys } from "../../lib/storage";
import { SidebarShell } from "../../components/shell/sidebar-shell";
import { RightSidebarShell } from "../../components/shell/right-sidebar-shell";
import { ContentShell } from "../../components/shell/content-shell";
import { ResizableDivider } from "../../components/shell/resizable-divider";
import { RouteSwitcher, type AppRoute } from "../sidebar/route-switcher";
import { SidebarView } from "../sidebar/sidebar-view";
import { ChatView } from "../chat/chat-view";
import { SettingsView } from "../settings/settings-view";
import { MemoryView } from "../memory/memory-view";
import { SecretsView } from "../secrets/secrets-view";
import { ProjectsView } from "../projects/projects-view";
import { DatabaseView } from "../database/database-view";
import { McpView } from "../mcp/mcp-view";
import { LocalModelsView } from "../local-models/local-models-view";
import { VersionMismatchBanner } from "./version-mismatch";

// Mac-side constants (ContentView.swift:4-15).
const SIDEBAR_DEFAULT = 372;
const SIDEBAR_MIN = 220;
const SIDEBAR_MAX = 558;
const RIGHT_SIDEBAR_DEFAULT = 720;
const RIGHT_SIDEBAR_MIN = 380;
const RIGHT_SIDEBAR_MAX = 1080;
const SETTINGS_SIDEBAR = 298;

export function MainShell() {
  const [route, setRoute] = useState<AppRoute>(
    () => storage.get<AppRoute>(StorageKeys.currentRoute) ?? "chat",
  );
  const [chatId, setChatId] = useState<string | null>(
    () => storage.get<string>(StorageKeys.lastChatId),
  );
  const [sidebarWidth, setSidebarWidth] = useState<number>(
    () => storage.get<number>(StorageKeys.sidebarWidth) ?? SIDEBAR_DEFAULT,
  );
  const [rightSidebarWidth, setRightSidebarWidth] = useState<number>(
    () => storage.get<number>(StorageKeys.rightSidebarWidth) ?? RIGHT_SIDEBAR_DEFAULT,
  );
  const [rightSidebarOpen] = useState<boolean>(
    () => storage.get<boolean>(StorageKeys.rightSidebarOpen) ?? false,
  );

  const newChat = useBridgeStore((s) => s.newChat);
  const conn = useBridgeStore((s) => s.connection);

  useEffect(() => {
    storage.set(StorageKeys.currentRoute, route);
  }, [route]);
  useEffect(() => {
    if (chatId) storage.set(StorageKeys.lastChatId, chatId);
  }, [chatId]);
  useEffect(() => {
    storage.set(StorageKeys.sidebarWidth, sidebarWidth);
  }, [sidebarWidth]);
  useEffect(() => {
    storage.set(StorageKeys.rightSidebarWidth, rightSidebarWidth);
  }, [rightSidebarWidth]);

  const isSettings = route === "settings";
  const leftWidth = isSettings ? SETTINGS_SIDEBAR : sidebarWidth;

  return (
    // Backdrop: sidebar blur fills the entire window so the content
    // panel's rounded edges reveal the sidebar tone, not the wallpaper.
    <div className="h-full sidebar-backdrop relative">
      {conn.kind === "version-mismatch" && (
        <div className="absolute inset-x-0 top-0 z-50">
          <VersionMismatchBanner serverVersion={conn.serverVersion} />
        </div>
      )}
      <div className="h-full flex">
        <SidebarShell width={leftWidth}>
          <RouteSwitcher current={route} onChange={setRoute} />
          <div className="flex-1 min-h-0 flex flex-col">
            {route === "chat" && (
              <SidebarView
                selectedChatId={chatId}
                onSelect={setChatId}
                onNew={() => {
                  const id = newChat("");
                  setChatId(id);
                }}
              />
            )}
          </div>
        </SidebarShell>

        {!isSettings && (
          <ResizableDivider
            width={sidebarWidth}
            min={SIDEBAR_MIN}
            max={SIDEBAR_MAX}
            onChange={setSidebarWidth}
            side="left"
          />
        )}

        <ContentShell rightSidebarOpen={rightSidebarOpen}>
          {route === "chat" && <ChatView chatId={chatId} />}
          {route === "projects" && <ProjectsView />}
          {route === "memory" && <MemoryView />}
          {route === "secrets" && <SecretsView />}
          {route === "database" && <DatabaseView />}
          {route === "mcp" && <McpView />}
          {route === "local-models" && <LocalModelsView />}
          {route === "settings" && <SettingsView />}
        </ContentShell>

        {rightSidebarOpen && (
          <ResizableDivider
            width={rightSidebarWidth}
            min={RIGHT_SIDEBAR_MIN}
            max={RIGHT_SIDEBAR_MAX}
            onChange={setRightSidebarWidth}
            side="right"
          />
        )}
        <RightSidebarShell width={rightSidebarWidth} open={rightSidebarOpen}>
          <div className="h-full p-4 text-[12.5px] text-[var(--color-fg-secondary)]">
            File preview slot
          </div>
        </RightSidebarShell>
      </div>
    </div>
  );
}
