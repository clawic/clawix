// Top of the sidebar: switches between the 8 main routes (chat, projects,
// memory, secrets, database, mcp, local-models, settings).
// Mac equivalent lives in SidebarTopChrome / SettingsSidebar selector;
// here it's a single inline list so the sidebar stays a single column.
import {
  ChatIcon,
  FolderOpenIcon,
  BrainIcon,
  KeyIcon,
  DatabaseIcon,
  PuzzleIcon,
  ServerIcon,
  SettingsIcon,
} from "../../icons";
import cx from "../../lib/cx";

export type AppRoute =
  | "chat"
  | "projects"
  | "memory"
  | "secrets"
  | "database"
  | "mcp"
  | "local-models"
  | "settings";

interface Props {
  current: AppRoute;
  onChange: (next: AppRoute) => void;
}

const ITEMS: { route: AppRoute; label: string; Icon: (p: { size?: number; className?: string }) => React.ReactElement }[] = [
  { route: "chat", label: "Chats", Icon: ChatIcon },
  { route: "projects", label: "Projects", Icon: FolderOpenIcon },
  { route: "memory", label: "Memory", Icon: BrainIcon },
  { route: "secrets", label: "Secrets", Icon: KeyIcon },
  { route: "database", label: "Database", Icon: DatabaseIcon },
  { route: "mcp", label: "MCP", Icon: PuzzleIcon },
  { route: "local-models", label: "Local models", Icon: ServerIcon },
  { route: "settings", label: "Settings", Icon: SettingsIcon },
];

export function RouteSwitcher({ current, onChange }: Props) {
  return (
    <nav className="px-2 pt-2 pb-1 space-y-0.5">
      {ITEMS.map((it) => (
        <button
          key={it.route}
          onClick={() => onChange(it.route)}
          className={cx(
            "group w-full flex items-center gap-2 px-2.5 h-8 rounded-[8px] text-left text-[12.5px] transition-colors",
            current === it.route
              ? "bg-[rgba(255,255,255,0.08)] text-[var(--color-fg)]"
              : "text-[var(--color-menu-row-text)] hover:bg-[rgba(255,255,255,0.04)]"
          )}
          style={{ fontVariationSettings: '"wght" 600' }}
        >
          <it.Icon size={14} className="shrink-0" />
          <span>{it.label}</span>
        </button>
      ))}
    </nav>
  );
}
