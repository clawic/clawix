/**
 * Memory mirrors the macOS Memory screen. Fully driven by RPC-style frames
 * to the daemon (read/write memory entries). The frames for memory are not
 * yet in the schema; we render the screen with a "Coming soon" hint that
 * points to the macOS app while keeping the layout ready for parity.
 */
import { BrainIcon } from "../../icons";

export function MemoryView() {
  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-3 border-b border-[var(--color-border)]">
        <BrainIcon size={16} className="text-[var(--color-fg-muted)]" />
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">Memory</h1>
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto py-10 px-6">
          <div className="rounded-[16px] border border-[var(--color-border)] bg-[var(--color-bg-elev-1)] p-6 space-y-3">
            <div className="text-[14px] font-medium tracking-[-0.01em]">Persistent memory</div>
            <p className="text-[12.5px] text-[var(--color-fg-muted)] leading-relaxed">
              Codex memory entries are managed on your Mac. Editing from the web requires a memory
              wire frame, which lands in a future schema bump. Until then, use the Memory panel in
              the Mac app to add or revise entries; they will be visible to your sessions here
              automatically.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
