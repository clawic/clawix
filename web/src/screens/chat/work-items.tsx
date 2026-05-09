/**
 * Renders WireWorkItem groups (the assistant's tool calls during a turn).
 * Mirrors the macOS WorkSummary disclosure.
 */
import { useState } from "react";
import type { WireWorkItem, WireWorkSummary } from "../../bridge/wire";
import {
  TerminalIcon,
  FileChipIcon,
  GlobeIcon,
  PuzzleIcon,
  SearchIcon,
  ChevronDownIcon,
  ChevronRightIcon,
} from "../../icons";
import cx from "../../lib/cx";

export function WorkSummary({ summary }: { summary: WireWorkSummary }) {
  const [open, setOpen] = useState(false);
  const elapsed = summary.endedAt
    ? Math.max(0, Math.round((Date.parse(summary.endedAt) - Date.parse(summary.startedAt)) / 1000))
    : null;
  const counts = countItems(summary.items);
  const summaryLine = [
    elapsed != null ? `Worked for ${elapsed}s` : "Working",
    ...buildCountLabels(counts),
  ].join(" · ");

  return (
    <div className="rounded-[12px] border border-[var(--color-border)] overflow-hidden">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-2 w-full px-3 py-2 text-[12px] text-[var(--color-fg-secondary)] hover:bg-[var(--color-card)]"
      >
        {open ? <ChevronDownIcon size={11} /> : <ChevronRightIcon size={11} />}
        <span>{summaryLine}</span>
      </button>
      {open && (
        <ul className="divide-y divide-[var(--color-border)] bg-[var(--color-card)]/40">
          {summary.items.map((item) => (
            <WorkItemRow key={item.id} item={item} />
          ))}
        </ul>
      )}
    </div>
  );
}

function WorkItemRow({ item }: { item: WireWorkItem }) {
  const Icon = iconFor(item.kind);
  return (
    <li className="flex items-start gap-2 px-3 py-2 text-[12px]">
      <Icon size={12} className="mt-[3px] text-[var(--color-fg-secondary)] shrink-0" />
      <div className="flex-1 min-w-0">
        <div className="text-[var(--color-fg)] truncate">{labelFor(item)}</div>
        {item.commandText && (
          <pre className="mt-1 whitespace-pre-wrap font-mono text-[11px] text-[var(--color-fg-secondary)] truncate">
            {item.commandText}
          </pre>
        )}
        {item.paths && item.paths.length > 0 && (
          <div className="mt-1 flex flex-wrap gap-1">
            {item.paths.map((p) => (
              <span key={p} className="font-mono text-[11px] text-[var(--color-fg-secondary)]">
                {p}
              </span>
            ))}
          </div>
        )}
      </div>
      <StatusDot status={item.status} />
    </li>
  );
}

function StatusDot({ status }: { status: WireWorkItem["status"] }) {
  return (
    <span
      className={cx(
        "size-2 rounded-full mt-1.5",
        status === "inProgress" && "bg-[var(--color-banner-danger-fg)] animate-pulse",
        status === "completed" && "bg-[var(--color-banner-ok-fg)]",
        status === "failed" && "bg-[var(--color-destructive)]",
      )}
    />
  );
}

function iconFor(kind: string) {
  switch (kind) {
    case "command":
      return TerminalIcon;
    case "fileChange":
    case "imageView":
      return FileChipIcon;
    case "webSearch":
      return GlobeIcon;
    case "mcpTool":
    case "dynamicTool":
      return PuzzleIcon;
    default:
      return SearchIcon;
  }
}

function labelFor(item: WireWorkItem): string {
  switch (item.kind) {
    case "command":
      return (item.commandActions ?? []).join(", ") || "Ran command";
    case "fileChange":
      return `Edited ${item.paths?.length ?? 0} file${(item.paths?.length ?? 0) === 1 ? "" : "s"}`;
    case "webSearch":
      return "Web search";
    case "mcpTool":
      return `${item.mcpServer ?? "MCP"} · ${item.mcpTool ?? "tool"}`;
    case "dynamicTool":
      return item.dynamicToolName ?? "Tool";
    case "imageGeneration":
      return "Generated image";
    case "imageView":
      return "Viewed image";
    default:
      return item.kind;
  }
}

function countItems(items: WireWorkItem[]) {
  const out: Record<string, number> = {};
  for (const i of items) out[i.kind] = (out[i.kind] ?? 0) + 1;
  return out;
}

function buildCountLabels(counts: Record<string, number>) {
  const parts: string[] = [];
  if (counts.command) parts.push(`Ran ${counts.command} command${counts.command === 1 ? "" : "s"}`);
  if (counts.fileChange) parts.push(`Edited ${counts.fileChange} file${counts.fileChange === 1 ? "" : "s"}`);
  if (counts.webSearch) parts.push(`${counts.webSearch} web search${counts.webSearch === 1 ? "" : "es"}`);
  if (counts.mcpTool) parts.push(`${counts.mcpTool} MCP call${counts.mcpTool === 1 ? "" : "s"}`);
  if (counts.imageGeneration) parts.push("Generated image");
  return parts;
}
