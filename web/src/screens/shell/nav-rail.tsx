/**
 * Vertical nav rail on the left. Replaces the macOS app's top-level
 * navigation between Chats / Projects / Memory / Settings / etc.
 */
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

export type NavRoute =
  | "chat"
  | "projects"
  | "memory"
  | "secrets"
  | "database"
  | "mcp"
  | "local-models"
  | "settings";

interface Props {
  current: NavRoute;
  onChange: (route: NavRoute) => void;
}

interface Item {
  route: NavRoute;
  label: string;
  Icon: (props: { size?: number; className?: string }) => React.ReactElement;
}

const ITEMS: Item[] = [
  { route: "chat", label: "Chat", Icon: ChatIcon },
  { route: "projects", label: "Projects", Icon: FolderOpenIcon },
  { route: "memory", label: "Memory", Icon: BrainIcon },
  { route: "secrets", label: "Secrets", Icon: KeyIcon },
  { route: "database", label: "Database", Icon: DatabaseIcon },
  { route: "mcp", label: "MCP", Icon: PuzzleIcon },
  { route: "local-models", label: "Local models", Icon: ServerIcon },
];

export function NavRail({ current, onChange }: Props) {
  return (
    <nav className="h-full w-[64px] shrink-0 border-r border-[var(--color-border)] bg-[var(--color-bg)] flex flex-col items-center py-3 gap-1">
      <div className="size-9 rounded-[10px] bg-[var(--color-bg-elev-3)] grid place-items-center mb-3 select-none">
        <span className="text-[13px] font-semibold tracking-[-0.02em]">Cl</span>
      </div>
      {ITEMS.map((it) => (
        <button
          key={it.route}
          onClick={() => onChange(it.route)}
          title={it.label}
          className={cx(
            "size-10 rounded-[12px] grid place-items-center transition-colors",
            current === it.route
              ? "bg-[var(--color-bg-elev-3)] text-[var(--color-fg)]"
              : "text-[var(--color-fg-muted)] hover:bg-[var(--color-bg-elev-1)] hover:text-[var(--color-fg)]",
          )}
        >
          <it.Icon size={16} />
        </button>
      ))}
      <div className="flex-1" />
      <button
        onClick={() => onChange("settings")}
        title="Settings"
        className={cx(
          "size-10 rounded-[12px] grid place-items-center transition-colors",
          current === "settings"
            ? "bg-[var(--color-bg-elev-3)] text-[var(--color-fg)]"
            : "text-[var(--color-fg-muted)] hover:bg-[var(--color-bg-elev-1)] hover:text-[var(--color-fg)]",
        )}
      >
        <SettingsIcon size={16} />
      </button>
    </nav>
  );
}
