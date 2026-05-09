/**
 * MCP config mirror. Shows the structural layout; live editing is gated
 * on dedicated MCP wire frames.
 */
import { PuzzleIcon } from "../../icons";

export function McpView() {
  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-3 border-b border-[var(--color-border)]">
        <PuzzleIcon size={16} className="text-[var(--color-fg-muted)]" />
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">MCP servers</h1>
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto py-10 px-6">
          <div className="rounded-[16px] border border-[var(--color-border)] bg-[var(--color-bg-elev-1)] p-6 space-y-3">
            <div className="text-[14px] font-medium tracking-[-0.01em]">Connected MCP servers</div>
            <p className="text-[12.5px] text-[var(--color-fg-muted)] leading-relaxed">
              MCP server configuration is owned by the Mac app. Web edits require a dedicated MCP
              wire frame; until then, manage servers from the Mac and the bridge will surface their
              tools to your sessions automatically.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
