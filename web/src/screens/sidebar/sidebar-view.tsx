// SidebarView mirror of SidebarView.swift. The sidebar inherits the
// global blur from the shell (no own bg fill); width is controlled by
// the shell's resizable column.
import { useMemo, useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import type { WireChat } from "../../bridge/wire";
import {
  ChatIcon,
  PinIcon,
  PlusIcon,
  SearchIcon,
  ArchiveIcon,
  ChevronDownIcon,
  ChevronRightIcon,
} from "../../icons";
import cx from "../../lib/cx";

interface Props {
  selectedChatId: string | null;
  onSelect: (chatId: string) => void;
  onNew: () => void;
}

export function SidebarView({ selectedChatId, onSelect, onNew }: Props) {
  const chats = useBridgeStore((s) => s.chats);
  const [query, setQuery] = useState("");
  const [showArchived, setShowArchived] = useState(false);

  const { pinned, recent, archived } = useMemo(() => groupChats(chats, query), [chats, query]);

  return (
    <aside className="h-full flex flex-col">
      <div className="px-3 pt-1 pb-2 flex items-center gap-2">
        <button
          onClick={onNew}
          className="grid place-items-center transition-colors size-8"
          style={{
            borderRadius: 8,
            background: "rgba(255,255,255,0.06)",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.10)")}
          onMouseLeave={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.06)")}
          title="New chat"
        >
          <PlusIcon size={14} />
        </button>
        <div
          className="flex items-center gap-2 flex-1"
          style={{
            height: 32,
            padding: "0 10px",
            borderRadius: 8,
            background: "rgba(255,255,255,0.06)",
            boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.06)",
          }}
        >
          <SearchIcon size={13} className="text-[var(--color-fg-secondary)]" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search"
            spellCheck={false}
            className="flex-1 bg-transparent outline-none text-[12.5px] placeholder:text-[var(--color-fg-tertiary)]"
            style={{ fontVariationSettings: '"wght" 600' }}
          />
        </div>
      </div>

      <div className="thin-scroll flex-1 overflow-y-auto px-2 pb-3 space-y-3">
        {pinned.length > 0 && (
          <SidebarGroup label="Pinned" icon={<PinIcon size={11} />}>
            {pinned.map((c) => (
              <SidebarRow
                key={c.id}
                chat={c}
                selected={c.id === selectedChatId}
                onClick={() => onSelect(c.id)}
              />
            ))}
          </SidebarGroup>
        )}

        <SidebarGroup label="Recent">
          {recent.length === 0 && (
            <div className="px-2 py-2 text-[12px] text-[var(--color-fg-tertiary)]">No chats yet</div>
          )}
          {recent.map((c) => (
            <SidebarRow
              key={c.id}
              chat={c}
              selected={c.id === selectedChatId}
              onClick={() => onSelect(c.id)}
            />
          ))}
        </SidebarGroup>

        {archived.length > 0 && (
          <div>
            <button
              onClick={() => setShowArchived((v) => !v)}
              className="flex items-center gap-1.5 px-2 py-1 w-full text-[11px] text-[var(--color-fg-secondary)] hover:text-[var(--color-fg)]"
              style={{ letterSpacing: "-0.01em", fontVariationSettings: '"wght" 700' }}
            >
              {showArchived ? <ChevronDownIcon size={10} /> : <ChevronRightIcon size={10} />}
              <ArchiveIcon size={11} />
              <span>Archived ({archived.length})</span>
            </button>
            {showArchived && (
              <div className="space-y-0.5 mt-1">
                {archived.map((c) => (
                  <SidebarRow
                    key={c.id}
                    chat={c}
                    selected={c.id === selectedChatId}
                    onClick={() => onSelect(c.id)}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </aside>
  );
}

function SidebarGroup({ label, icon, children }: { label: string; icon?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div>
      <div
        className="flex items-center gap-1.5 px-2 py-1 text-[11px] text-[var(--color-menu-header)]"
        style={{ letterSpacing: "-0.01em", fontVariationSettings: '"wght" 700' }}
      >
        {icon}
        <span>{label}</span>
      </div>
      <div className="space-y-0.5">{children}</div>
    </div>
  );
}

function SidebarRow({ chat, selected, onClick }: { chat: WireChat; selected: boolean; onClick: () => void }) {
  const last = chat.lastMessageAt ?? chat.createdAt;
  return (
    <button
      onClick={onClick}
      className={cx(
        "group flex flex-col gap-0.5 w-full text-left transition-[background-color] duration-[150ms] ease-[var(--ease-row)]",
      )}
      style={{
        padding: "8px 10px",
        borderRadius: 8,
        background: selected ? "rgba(255,255,255,0.10)" : "transparent",
      }}
      onMouseEnter={(e) => {
        if (!selected) e.currentTarget.style.background = "rgba(255,255,255,0.04)";
      }}
      onMouseLeave={(e) => {
        if (!selected) e.currentTarget.style.background = "transparent";
      }}
    >
      <div className="flex items-center gap-2">
        <ChatIcon size={13} className="text-[var(--color-fg-secondary)] shrink-0" />
        <span
          className="flex-1 truncate text-[13px]"
          style={{ fontVariationSettings: '"wght" 600' }}
        >
          {chat.title || "Untitled"}
        </span>
        {chat.hasActiveTurn && (
          <span className="size-1.5 rounded-full bg-[var(--color-pastel-blue)] animate-pulse" />
        )}
        {chat.lastTurnInterrupted && !chat.hasActiveTurn && (
          <span className="text-[10px] text-[var(--color-banner-danger-fg)]">⏸</span>
        )}
      </div>
      {chat.lastMessagePreview && (
        <div className="pl-[20px] text-[11.5px] text-[var(--color-fg-tertiary)] truncate">
          {chat.lastMessagePreview}
        </div>
      )}
      <div className="pl-[20px] text-[10px] text-[var(--color-fg-tertiary)] flex items-center gap-1.5">
        <span>{relativeTime(last)}</span>
        {chat.branch && <span>· {chat.branch}</span>}
      </div>
    </button>
  );
}

function groupChats(chats: WireChat[], query: string) {
  const q = query.trim().toLowerCase();
  const filter = (c: WireChat) =>
    !q ||
    c.title.toLowerCase().includes(q) ||
    (c.lastMessagePreview ?? "").toLowerCase().includes(q);
  const visible = chats.filter(filter);
  return {
    pinned: visible.filter((c) => c.isPinned && !c.isArchived),
    recent: visible.filter((c) => !c.isPinned && !c.isArchived),
    archived: visible.filter((c) => c.isArchived),
  };
}

function relativeTime(iso: string): string {
  const ts = Date.parse(iso);
  if (Number.isNaN(ts)) return "";
  const diff = Date.now() - ts;
  const m = 60_000;
  if (diff < m) return "now";
  if (diff < 60 * m) return `${Math.floor(diff / m)}m`;
  if (diff < 24 * 60 * m) return `${Math.floor(diff / (60 * m))}h`;
  if (diff < 7 * 24 * 60 * m) return `${Math.floor(diff / (24 * 60 * m))}d`;
  return new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
